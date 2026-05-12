#!/usr/bin/env bash
# claude-fallback-nvidia — interactive installer for Linux/macOS.
#
# Sets up a local LiteLLM proxy that routes to NVIDIA-hosted free-tier models
# (Kimi K2.6, Qwen3-Next 80B). Adapts to what's available on the machine:
#
#   Mode A — claude:     installs claude-deep / claude-fast (needs Claude Code)
#   Mode B — aider:      installs aider-deep / aider-fast (needs Aider)
#   Mode C — both:       installs all four wrappers
#   Mode D — proxy-only: just the proxy, you bring your own client
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES_DIR="$REPO_DIR/linux/templates"

# ── Colors ───────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'
  C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_BLUE=""
fi
say()   { echo "${C_BLUE}→${C_RESET} $*"; }
ok()    { echo "${C_GREEN}✓${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}!${C_RESET} $*"; }
fail()  { echo "${C_RED}✗${C_RESET} $*" >&2; }
hr()    { echo "${C_BOLD}────────────────────────────────────────────${C_RESET}"; }

# ── 1. Pre-flight ─────────────────────────────────────────────────────────
hr
say "claude-fallback-nvidia installer"
hr

INSTALL_DIR="${LITELLM_INSTALL_DIR:-$HOME/litellm-proxy}"
BIN_DIR="${LITELLM_BIN_DIR:-$HOME/.local/bin}"
PORT="${LITELLM_PORT:-4000}"

say "checking dependencies..."

# python3
if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 not found. Install Python 3.10+ first."
  exit 1
fi
PY_VERSION="$(python3 --version 2>&1 | awk '{print $2}')"
ok "python3: $PY_VERSION"

# python3-venv
if ! python3 -m venv --help >/dev/null 2>&1; then
  fail "python3 venv module not available."
  echo "    Debian/Ubuntu/Mint: sudo apt install python3-venv"
  echo "    Fedora:             sudo dnf install python3-virtualenv"
  exit 1
fi

# curl
if ! command -v curl >/dev/null 2>&1; then
  fail "curl not found. Install it first (sudo apt install curl)."
  exit 1
fi

# port
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "(:|\\.)$PORT\$"; then
  fail "port $PORT is already in use."
  echo "    Free it (lsof -i :$PORT then kill), or set LITELLM_PORT and retry."
  exit 1
fi
ok "port $PORT is free"

# ── 2. Detect CLI clients + decide install mode ──────────────────────────
hr
HAS_CLAUDE=false
HAS_AIDER=false
command -v claude >/dev/null 2>&1 && HAS_CLAUDE=true
command -v aider  >/dev/null 2>&1 && HAS_AIDER=true

INSTALL_CLAUDE=false
INSTALL_AIDER=false

if $HAS_CLAUDE && $HAS_AIDER; then
  ok "found Claude Code: $(command -v claude)"
  ok "found Aider: $(command -v aider)"
  echo "Both clients are available. Will install wrappers for both."
  INSTALL_CLAUDE=true
  INSTALL_AIDER=true

elif $HAS_CLAUDE && ! $HAS_AIDER; then
  ok "found Claude Code: $(command -v claude)"
  INSTALL_CLAUDE=true
  read -r -p "Also install Aider (open-source CLI alternative)? [y/N] " ans
  [[ "${ans,,}" =~ ^y(es)?$ ]] && INSTALL_AIDER=true

elif ! $HAS_CLAUDE && $HAS_AIDER; then
  warn "Claude Code not found; Aider is available."
  ok "found Aider: $(command -v aider)"
  INSTALL_AIDER=true
  echo
  echo "Options:"
  echo "  1) Install Claude Code automatically (binary, no Anthropic account required to download)"
  echo "  2) Continue with Aider only (recommended if you don't want an Anthropic account)"
  read -r -p "Choice [1/2, default 2]: " choice
  if [[ "$choice" == "1" ]]; then
    say "downloading Claude Code installer..."
    if curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh; then
      bash /tmp/claude-install.sh && INSTALL_CLAUDE=true
      command -v claude >/dev/null 2>&1 || warn "claude installed but not yet in PATH; open a new shell after install."
    else
      warn "could not download Claude Code installer; continuing with Aider only."
    fi
  fi

else
  warn "Neither Claude Code nor Aider found in PATH."
  echo
  echo "Pick an install mode:"
  echo "  1) Install Claude Code     — requires an Anthropic account to use"
  echo "  2) Install Aider           — open-source, NO Anthropic account required (recommended)"
  echo "  3) Install both"
  echo "  4) Proxy only              — you'll bring your own client (Cline, OpenCode, etc.)"
  echo
  echo "If you don't have a Claude / Anthropic account and just want the free NVIDIA models,"
  echo "press Enter (defaults to 2)."
  read -r -p "Choice [1/2/3/4, default 2]: " choice
  case "${choice:-2}" in
    1)
      say "downloading Claude Code installer..."
      curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
      bash /tmp/claude-install.sh && INSTALL_CLAUDE=true || fail "Claude Code install failed."
      ;;
    2) INSTALL_AIDER=true ;;
    3)
      say "downloading Claude Code installer..."
      curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
      bash /tmp/claude-install.sh && INSTALL_CLAUDE=true || warn "Claude Code install failed; continuing with Aider."
      INSTALL_AIDER=true
      ;;
    4)
      warn "proxy-only mode — no CLI wrappers will be installed."
      ;;
    *)
      fail "invalid choice."
      exit 1
      ;;
  esac
fi

# Install Aider via pip/pipx if requested and not yet present.
# Robust against PEP 668 ("externally-managed-environment") on Debian/Ubuntu/Mint 23.04+.
if $INSTALL_AIDER && ! command -v aider >/dev/null 2>&1; then
  AIDER_INSTALLED=false

  # Attempt 1: pip --user (works on older distros + venvs)
  say "installing Aider via pip --user (this may take a minute) ..."
  if python3 -m pip install --user --quiet aider-chat 2>/dev/null; then
    ok "aider installed via pip --user"
    AIDER_INSTALLED=true
  fi

  # Attempt 2: pipx (the right tool on modern Debian/Ubuntu/Mint)
  if ! $AIDER_INSTALLED; then
    if ! command -v pipx >/dev/null 2>&1; then
      say "pipx not found; attempting to install it (needed on modern Debian/Ubuntu/Mint) ..."
      # Try apt first (most reliable on Debian-family), then pip --user as fallback.
      if command -v apt-get >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        sudo apt-get install -y pipx >/dev/null 2>&1 || true
      fi
      if ! command -v pipx >/dev/null 2>&1; then
        python3 -m pip install --user --quiet --break-system-packages pipx 2>/dev/null || true
        # Add ~/.local/bin to PATH for the current shell so we can use pipx now.
        export PATH="$HOME/.local/bin:$PATH"
      fi
    fi
    if command -v pipx >/dev/null 2>&1; then
      say "installing Aider via pipx ..."
      if pipx install aider-chat >/dev/null 2>&1; then
        ok "aider installed via pipx"
        AIDER_INSTALLED=true
        # Make sure pipx's bin dir is in PATH for the current shell so smoke tests find aider.
        pipx ensurepath >/dev/null 2>&1 || true
        export PATH="$HOME/.local/bin:$PATH"
      fi
    fi
  fi

  # Attempt 3: last-resort --break-system-packages on PEP 668 systems
  if ! $AIDER_INSTALLED; then
    if python3 -m pip install --user --break-system-packages --quiet aider-chat 2>/dev/null; then
      ok "aider installed (--break-system-packages)"
      AIDER_INSTALLED=true
    fi
  fi

  # If all three attempts failed we have to decide based on the install mode:
  #   - Aider-only (no Claude planned) → ABORT with clear instructions, since
  #     copying aider-deep/aider-fast wrappers without an `aider` binary would
  #     give a confusing error later.
  #   - Mixed (Claude + Aider) → warn and continue with Claude wrappers only.
  if ! $AIDER_INSTALLED; then
    if $INSTALL_CLAUDE; then
      warn "could not install Aider. Continuing with Claude wrappers only."
      warn "To add Aider later:  pipx install aider-chat  (or)  pip install --user aider-chat"
      INSTALL_AIDER=false
    else
      fail "could not install Aider, and no other CLI was selected."
      echo
      echo "Install Aider manually, then re-run this script:"
      echo "    sudo apt install pipx      # Debian/Ubuntu/Mint"
      echo "    pipx install aider-chat"
      echo "    pipx ensurepath"
      echo
      echo "Or pick a different mode by re-running 'bash linux/install.sh'."
      exit 1
    fi
  fi
fi

# ── 3. Existing install? ─────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR" ]]; then
  warn "an install already exists at $INSTALL_DIR"
  read -r -p "Overwrite? [y/N] " ans
  case "${ans,,}" in
    y|yes)
      BACKUP="$INSTALL_DIR.backup-$(date +%Y%m%d-%H%M%S)"
      mv "$INSTALL_DIR" "$BACKUP"
      ok "moved existing install to $BACKUP"
      ;;
    *) echo "aborted."; exit 0 ;;
  esac
fi

# ── 4. NVIDIA API key ────────────────────────────────────────────────────
hr
echo "Get a free NVIDIA API key at: https://build.nvidia.com  (~5000 credits/month)"
echo "Paste it here. Must start with 'nvapi-'. Input is hidden."
while true; do
  read -r -s -p "NVIDIA_API_KEY: " NVIDIA_API_KEY
  echo
  [[ "$NVIDIA_API_KEY" =~ ^nvapi-.+$ ]] && break
  warn "invalid format — should start with 'nvapi-'. try again."
done
ok "API key recorded (length: ${#NVIDIA_API_KEY})"

# ── 5. Create venv + install LiteLLM ─────────────────────────────────────
hr
say "creating Python venv at $INSTALL_DIR/.venv ..."
mkdir -p "$INSTALL_DIR"
python3 -m venv "$INSTALL_DIR/.venv"
ok "venv created"

say "installing LiteLLM (1-2 minutes) ..."
"$INSTALL_DIR/.venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/.venv/bin/pip" install --quiet 'litellm[proxy]'
LITELLM_VERSION="$("$INSTALL_DIR/.venv/bin/litellm" --version 2>&1 | head -1)"
ok "$LITELLM_VERSION"

# ── 6. Generate master key + write env.sh ────────────────────────────────
if command -v openssl >/dev/null 2>&1; then
  MASTER_KEY="sk-litellm-$(openssl rand -hex 16)"
else
  MASTER_KEY="sk-litellm-$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
fi

cat > "$INSTALL_DIR/env.sh" <<EOF
# claude-fallback-nvidia — generated $(date -Iseconds)
export NVIDIA_API_KEY=${NVIDIA_API_KEY}
export LITELLM_MASTER_KEY=${MASTER_KEY}
export LITELLM_PORT=${PORT}
EOF
chmod 600 "$INSTALL_DIR/env.sh"
ok "wrote env.sh (perms: 600)"

# ── 7. Install proxy templates ───────────────────────────────────────────
say "installing config + scripts + boost ..."
cp "$TEMPLATES_DIR/config.yaml"      "$INSTALL_DIR/config.yaml"
cp "$TEMPLATES_DIR/start.sh"         "$INSTALL_DIR/start.sh"
cp "$TEMPLATES_DIR/stop.sh"          "$INSTALL_DIR/stop.sh"
cp "$TEMPLATES_DIR/custom_boost.py"  "$INSTALL_DIR/custom_boost.py"
cp "$TEMPLATES_DIR/system_boost.md"  "$INSTALL_DIR/system_boost.md"
chmod +x "$INSTALL_DIR/start.sh" "$INSTALL_DIR/stop.sh"
ok "installed proxy to $INSTALL_DIR"

# ── 8. Install wrappers ──────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
INSTALLED_WRAPPERS=()

if $INSTALL_CLAUDE; then
  cp "$TEMPLATES_DIR/claude-deep" "$BIN_DIR/claude-deep"
  cp "$TEMPLATES_DIR/claude-fast" "$BIN_DIR/claude-fast"
  chmod +x "$BIN_DIR/claude-deep" "$BIN_DIR/claude-fast"
  INSTALLED_WRAPPERS+=("claude-deep" "claude-fast")
fi
if $INSTALL_AIDER; then
  cp "$TEMPLATES_DIR/aider-deep" "$BIN_DIR/aider-deep"
  cp "$TEMPLATES_DIR/aider-fast" "$BIN_DIR/aider-fast"
  chmod +x "$BIN_DIR/aider-deep" "$BIN_DIR/aider-fast"
  INSTALLED_WRAPPERS+=("aider-deep" "aider-fast")
fi

# Patch INSTALL_DIR default if non-standard
if [[ "$INSTALL_DIR" != "$HOME/litellm-proxy" ]] && (( ${#INSTALLED_WRAPPERS[@]} > 0 )); then
  for w in "${INSTALLED_WRAPPERS[@]}"; do
    sed -i.bak "s|\$HOME/litellm-proxy|$INSTALL_DIR|g" "$BIN_DIR/$w"
    rm -f "$BIN_DIR/$w.bak"
  done
fi

if (( ${#INSTALLED_WRAPPERS[@]} > 0 )); then
  ok "installed wrappers: ${INSTALLED_WRAPPERS[*]}"
else
  ok "no CLI wrappers installed (proxy-only mode)"
fi

# Warn if BIN_DIR not in PATH
if (( ${#INSTALLED_WRAPPERS[@]} > 0 )); then
  case ":$PATH:" in
    *":$BIN_DIR:"*) ok "$BIN_DIR is in PATH" ;;
    *)
      warn "$BIN_DIR is NOT in PATH"
      echo "    Add this to ~/.bashrc (or ~/.zshrc) and re-source:"
      echo "      export PATH=\"$BIN_DIR:\$PATH\""
      ;;
  esac
fi

# ── 9. Start proxy ───────────────────────────────────────────────────────
hr
say "starting proxy ..."
"$INSTALL_DIR/start.sh"

say "waiting for proxy to come up ..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/health/liveness" >/dev/null 2>&1; then
    ok "proxy is alive"
    break
  fi
  sleep 1
  if [[ $i -eq 10 ]]; then
    fail "proxy failed to come up. Last 30 lines of proxy.log:"
    tail -30 "$INSTALL_DIR/proxy.log"
    exit 1
  fi
done

# ── 10. Smoke test ───────────────────────────────────────────────────────
say "smoke-testing qwen3-next route ..."
RESP=$(curl -sS --max-time 60 -X POST "http://127.0.0.1:$PORT/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $MASTER_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"qwen3-next","max_tokens":10,"messages":[{"role":"user","content":"reply ok"}]}')
if echo "$RESP" | grep -q '"type":"message"'; then
  ok "qwen3-next responded"
else
  fail "qwen3-next test failed:"
  echo "$RESP" | head -c 500
  warn "the proxy is running but routing failed. Check NVIDIA_API_KEY validity."
  exit 1
fi

say "smoke-testing kimi-k2 route (may take ~30s) ..."
RESP=$(curl -sS --max-time 90 -X POST "http://127.0.0.1:$PORT/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $MASTER_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"kimi-k2","max_tokens":10,"messages":[{"role":"user","content":"reply ok"}]}')
if echo "$RESP" | grep -q '"type":"message"'; then
  ok "kimi-k2 responded"
else
  warn "kimi-k2 test failed (free tier may be saturated). qwen3-next still works."
fi

# ── 11. Done ─────────────────────────────────────────────────────────────
hr
ok "${C_BOLD}install complete${C_RESET}"
echo
if $INSTALL_CLAUDE; then
  echo "  Claude wrappers:"
  echo "    ${C_BOLD}claude-deep${C_RESET}   →  Kimi K2.6"
  echo "    ${C_BOLD}claude-fast${C_RESET}   →  Qwen3-Next 80B"
fi
if $INSTALL_AIDER; then
  echo "  Aider wrappers:"
  echo "    ${C_BOLD}aider-deep${C_RESET}    →  Kimi K2.6"
  echo "    ${C_BOLD}aider-fast${C_RESET}    →  Qwen3-Next 80B"
fi
if ! $INSTALL_CLAUDE && ! $INSTALL_AIDER; then
  echo "  Proxy-only. Point any OpenAI/Anthropic-compatible client at:"
  echo "    base URL: http://127.0.0.1:$PORT"
  echo "    api key:  (in $INSTALL_DIR/env.sh as LITELLM_MASTER_KEY)"
  echo "    models:   kimi-k2, qwen3-next"
fi
echo
echo "  Proxy:"
echo "    start: $INSTALL_DIR/start.sh"
echo "    stop:  $INSTALL_DIR/stop.sh"
echo "    log:   $INSTALL_DIR/proxy.log"
echo
echo "  Open a new terminal (or re-source PATH) and try one of the wrappers."
echo
