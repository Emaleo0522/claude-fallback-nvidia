#!/usr/bin/env bash
# claude-fallback-nvidia — interactive installer for Linux/macOS.
# Sets up a local LiteLLM proxy + claude-deep / claude-fast wrappers that route
# Claude Code to NVIDIA-hosted free-tier models.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES_DIR="$REPO_DIR/linux/templates"

# ── Colors (only if stdout is a tty) ────────────────────────────────────────
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

# ── 1. Pre-flight ───────────────────────────────────────────────────────────
hr
say "claude-fallback-nvidia installer"
hr

INSTALL_DIR="${LITELLM_INSTALL_DIR:-$HOME/litellm-proxy}"
BIN_DIR="${LITELLM_BIN_DIR:-$HOME/.local/bin}"
PORT="${LITELLM_PORT:-4000}"

say "checking dependencies..."

# claude
if ! command -v claude >/dev/null 2>&1; then
  fail "Claude Code (\`claude\`) is not in PATH."
  echo "    Install it first: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi
CLAUDE_BIN="$(command -v claude)"
ok "found claude: $CLAUDE_BIN"

# python3
if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 not found. Install Python 3.10+ first."
  exit 1
fi
PY_VERSION="$(python3 --version 2>&1 | awk '{print $2}')"
ok "found python3: $PY_VERSION"

# python3-venv (probe by trying to create a temporary venv)
if ! python3 -m venv --help >/dev/null 2>&1; then
  fail "python3 venv module is not available."
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

# ── 2. Existing install? ────────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR" ]]; then
  warn "an install already exists at $INSTALL_DIR"
  read -r -p "Overwrite? [y/N] " ans
  case "${ans,,}" in
    y|yes)
      BACKUP="$INSTALL_DIR.backup-$(date +%Y%m%d-%H%M%S)"
      mv "$INSTALL_DIR" "$BACKUP"
      ok "moved existing install to $BACKUP"
      ;;
    *)
      echo "aborted."
      exit 0
      ;;
  esac
fi

# ── 3. NVIDIA API key ───────────────────────────────────────────────────────
hr
echo "Get a free NVIDIA API key at: https://build.nvidia.com  (~5000 credits/month)"
echo "Paste it here. It must start with 'nvapi-'. Input is hidden."
while true; do
  read -r -s -p "NVIDIA_API_KEY: " NVIDIA_API_KEY
  echo
  if [[ "$NVIDIA_API_KEY" =~ ^nvapi-.+$ ]]; then
    break
  fi
  warn "invalid format — should start with 'nvapi-'. try again."
done
ok "API key recorded (length: ${#NVIDIA_API_KEY})"

# ── 4. Create venv + install LiteLLM ────────────────────────────────────────
hr
say "creating Python venv at $INSTALL_DIR/.venv ..."
mkdir -p "$INSTALL_DIR"
python3 -m venv "$INSTALL_DIR/.venv"
ok "venv created"

say "installing LiteLLM (this can take 1-2 minutes) ..."
"$INSTALL_DIR/.venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/.venv/bin/pip" install --quiet 'litellm[proxy]'
LITELLM_VERSION="$("$INSTALL_DIR/.venv/bin/litellm" --version 2>&1 | head -1)"
ok "$LITELLM_VERSION"

# ── 5. Generate master key + write env.sh ───────────────────────────────────
if command -v openssl >/dev/null 2>&1; then
  MASTER_KEY="sk-litellm-$(openssl rand -hex 16)"
else
  MASTER_KEY="sk-litellm-$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
fi

cat > "$INSTALL_DIR/env.sh" <<EOF
# claude-fallback-nvidia — generated $(date -Iseconds)
# Source this file to load the proxy credentials.
export NVIDIA_API_KEY=${NVIDIA_API_KEY}
export LITELLM_MASTER_KEY=${MASTER_KEY}
export LITELLM_PORT=${PORT}
EOF
chmod 600 "$INSTALL_DIR/env.sh"
ok "wrote env.sh (perms: 600)"

# ── 6. Install templates ────────────────────────────────────────────────────
say "installing config + scripts ..."
cp "$TEMPLATES_DIR/config.yaml" "$INSTALL_DIR/config.yaml"
cp "$TEMPLATES_DIR/start.sh"    "$INSTALL_DIR/start.sh"
cp "$TEMPLATES_DIR/stop.sh"     "$INSTALL_DIR/stop.sh"
chmod +x "$INSTALL_DIR/start.sh" "$INSTALL_DIR/stop.sh"
ok "installed to $INSTALL_DIR"

# ── 7. Install wrappers ────────────────────────────────────────────────────
say "installing wrappers to $BIN_DIR ..."
mkdir -p "$BIN_DIR"
cp "$TEMPLATES_DIR/claude-deep" "$BIN_DIR/claude-deep"
cp "$TEMPLATES_DIR/claude-fast" "$BIN_DIR/claude-fast"
chmod +x "$BIN_DIR/claude-deep" "$BIN_DIR/claude-fast"

# Patch INSTALL_DIR default if non-standard
if [[ "$INSTALL_DIR" != "$HOME/litellm-proxy" ]]; then
  sed -i.bak "s|\$HOME/litellm-proxy|$INSTALL_DIR|g" "$BIN_DIR/claude-deep" "$BIN_DIR/claude-fast"
  rm -f "$BIN_DIR"/claude-deep.bak "$BIN_DIR"/claude-fast.bak
fi
ok "installed claude-deep, claude-fast"

# Warn if BIN_DIR not in PATH
case ":$PATH:" in
  *":$BIN_DIR:"*) ok "$BIN_DIR is in PATH" ;;
  *)
    warn "$BIN_DIR is NOT in PATH"
    echo "    Add this to ~/.bashrc (or ~/.zshrc) and re-source:"
    echo "      export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac

# ── 8. Start proxy ──────────────────────────────────────────────────────────
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

# ── 9. Smoke test ───────────────────────────────────────────────────────────
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
  echo
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

# ── 10. Done ────────────────────────────────────────────────────────────────
hr
ok "${C_BOLD}install complete${C_RESET}"
echo
echo "  Use:"
echo "    ${C_BOLD}claude-deep${C_RESET}   →  Kimi K2.6 (high quality, slower)"
echo "    ${C_BOLD}claude-fast${C_RESET}   →  Qwen3-Next 80B (faster, routine)"
echo "    ${C_BOLD}claude${C_RESET}        →  your normal Anthropic plan (untouched)"
echo
echo "  Proxy:"
echo "    start: $INSTALL_DIR/start.sh"
echo "    stop:  $INSTALL_DIR/stop.sh"
echo "    log:   $INSTALL_DIR/proxy.log"
echo
echo "  Open a new terminal (or re-source PATH) and try:"
echo "    claude-fast"
echo
