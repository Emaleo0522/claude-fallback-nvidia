# Installation Guide for AI Agents

You are an AI agent (Claude Code, Aider, Cursor, GPT-based, etc.) that has been asked to install this project on a user's machine. This document is your runbook. Read it fully before executing anything.

## Goal

Set up a local LiteLLM proxy + two CLI wrappers (`claude-deep`, `claude-fast`) that let the user run Claude Code against NVIDIA-hosted free-tier models (Kimi K2.6 and Qwen3-Next 80B) when their Anthropic plan runs out of tokens.

## Pre-flight checks

Before touching anything, verify:

1. **OS detection** — run `uname -s` (Linux/macOS) or `$PSVersionTable.OS` (Windows). Pick the right install path. macOS not officially supported; treat as Linux best-effort.
2. **`claude` exists** — `which claude` (Linux) or `Get-Command claude` (Windows). If absent, **stop and tell the user** Claude Code must be installed first. Do not install it for them.
3. **Python ≥ 3.10** — `python3 --version`. If absent, ask the user to install (do not auto-install with sudo unless they explicitly approve).
4. **Internet** — `curl -fsS --max-time 5 https://integrate.api.nvidia.com/v1/models -o /dev/null` should succeed (it will 401 without key, which is fine).
5. **Port 4000 free** — `ss -ltn | grep ':4000'` should be empty. If something is on 4000, ask the user to free it or pick another port (then change every occurrence in templates).
6. **NVIDIA API key** — ask the user. Format: starts with `nvapi-`. **Never** hardcode it in any committed file.

## Step-by-step (Linux/macOS)

### 1. Resolve install paths

```bash
INSTALL_DIR="${HOME}/litellm-proxy"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$INSTALL_DIR" "$BIN_DIR"
```

If `$BIN_DIR` is not in PATH, append `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` (or `~/.zshrc`) and tell the user to `source` it.

### 2. Create venv + install LiteLLM

```bash
python3 -m venv "$INSTALL_DIR/.venv"
"$INSTALL_DIR/.venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/.venv/bin/pip" install --quiet 'litellm[proxy]'
```

If `python3 -m venv` fails with "ensurepip is not available", **stop** and tell the user to run `sudo apt install python3-venv` (Ubuntu/Mint/Debian) or the equivalent. Do not run sudo commands without explicit user authorization.

### 3. Generate master key

```bash
MASTER_KEY="sk-litellm-$(openssl rand -hex 16)"
```

If `openssl` is unavailable, fall back to `python3 -c "import secrets; print('sk-litellm-'+secrets.token_hex(16))"`.

### 4. Write `env.sh`

```bash
cat > "$INSTALL_DIR/env.sh" <<EOF
export NVIDIA_API_KEY=${NVIDIA_API_KEY}
export LITELLM_MASTER_KEY=${MASTER_KEY}
EOF
chmod 600 "$INSTALL_DIR/env.sh"
```

`${NVIDIA_API_KEY}` must come from user input, not from any file in the repo.

### 5. Copy templates

Copy these from this repo's `linux/templates/` to `$INSTALL_DIR/`:
- `config.yaml`
- `start.sh`
- `stop.sh`

Make the scripts executable: `chmod +x "$INSTALL_DIR"/{start,stop}.sh`.

### 6. Install wrappers

Copy `linux/templates/claude-deep` and `linux/templates/claude-fast` to `$BIN_DIR/`. Edit each one to substitute:
- `__PROXY_URL__` → `http://127.0.0.1:4000`
- `__PROXY_TOKEN__` → the master key generated in step 3
- `__INSTALL_DIR__` → the resolved `$INSTALL_DIR`
- `__CLAUDE_BIN__` → output of `which claude`

`chmod +x "$BIN_DIR"/{claude-deep,claude-fast}`.

### 7. Start the proxy

```bash
"$INSTALL_DIR/start.sh"
```

Wait up to 8 seconds, then probe:

```bash
curl -fsS --max-time 5 http://127.0.0.1:4000/health/liveness
```

Expected output: `"I'm alive!"`.

### 8. Smoke-test routing

```bash
curl -sS --max-time 60 -X POST http://127.0.0.1:4000/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $MASTER_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"qwen3-next","max_tokens":20,"messages":[{"role":"user","content":"reply ok"}]}'
```

A successful response will be JSON with `"type":"message"` and a non-empty `content`. If it 4xx/5xx's:
- `400 Unsupported parameter`: add the param name to `additional_drop_params` in `config.yaml` and restart proxy.
- `401`: `NVIDIA_API_KEY` is wrong. Re-check.
- `503` / `Function id ... DEGRADED`: NVIDIA disabled the model. Pick another from `list-nvidia-models.sh` (in `tools/`).

Repeat for `kimi-k2`.

### 9. Report to user

Tell the user:
- The proxy is running on `http://127.0.0.1:4000`, PID at `$INSTALL_DIR/proxy.pid`.
- Use `claude-deep` for complex tasks, `claude-fast` for routine ones.
- The plain `claude` command still works against Anthropic.
- To stop the proxy: `$INSTALL_DIR/stop.sh`. To restart: `$INSTALL_DIR/start.sh`.

## Step-by-step (Windows / PowerShell)

The Windows install mirrors the Linux flow but uses different paths and tooling. See `windows/install.ps1` — when in doubt, follow that script as authoritative. Key differences:

- `INSTALL_DIR` defaults to `$env:USERPROFILE\litellm-proxy`
- `BIN_DIR` defaults to `$env:USERPROFILE\bin` (must be added to PATH manually if not there)
- venv is created with the same `python -m venv`; activation is `.\.venv\Scripts\Activate.ps1`
- `start.ps1` uses `Start-Process` for background; PID is stored in `proxy.pid`
- Wrappers are `.ps1` files; users run `claude-deep.ps1` (or alias them in `$PROFILE`)
- `chmod` is irrelevant; lock `env.ps1` with NTFS ACL: `icacls env.ps1 /inheritance:r /grant:r "$env:USERNAME:R"`

## What you must NOT do

- Do not commit, log, or print the user's NVIDIA API key.
- Do not run `sudo` / elevation without explicit user authorization for that exact command.
- Do not change `claude` itself or its config (`~/.claude/settings.json`). The wrappers work alongside it.
- Do not silently overwrite an existing `~/litellm-proxy/` if the user has one. Detect, ask, and back up first.
- Do not promise the wrappers match Claude's quality. Be honest: tool-use fidelity is lower with non-Claude models.

## Failure modes you will hit

| Symptom | Cause | Fix |
|---|---|---|
| `port 4000 already in use` | Another process bound it | `lsof -i :4000` (Linux) / `Get-NetTCPConnection -LocalPort 4000` (Windows) — kill it or change the port |
| `litellm: command not found` | venv not activated, or pip install failed | Re-run pip install inside the venv |
| `BadRequestError: Unsupported parameter X` | Anthropic sent a param NVIDIA doesn't accept | Add `X` to `additional_drop_params` in `config.yaml`, restart proxy |
| `Function id ... DEGRADED cannot be invoked` | NVIDIA pulled the model | Switch to a different model id in `config.yaml` |
| First call hangs > 60s | Free-tier queue saturated | Retry. Free tier has no SLA. |
| `401 from NVIDIA` | Bad/missing/expired key | Re-issue key at build.nvidia.com |
| Wrapper runs but `claude` says "model not found" | Catch-all `*` missing in config | Ensure `model_name: "*"` entry exists in `config.yaml` |

## When to ask the user instead of acting

- Choosing which models to map (defaults are fine; ask only if the user said something specific)
- Enabling autostart on boot (do **not** do this without permission)
- Modifying shell profiles (`~/.bashrc`, `$PROFILE`) — ask first, show the diff
- Replacing an existing install
