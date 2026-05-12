# claude-fallback-nvidia

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/platform-linux-informational)](#linux--macos)
[![Platform: Windows](https://img.shields.io/badge/platform-windows-informational)](#windows)
[![Status: Beta](https://img.shields.io/badge/status-beta-orange)](#caveats--limitations)

> Run **Claude Code** against **NVIDIA-hosted free-tier models** when your Anthropic plan tokens run out — without ever leaving the `claude` CLI you already know.

A local LiteLLM proxy translates between Anthropic's Messages API (what Claude Code speaks) and NVIDIA's OpenAI-compatible endpoint. Depending on which CLI you have installed, the installer hands you ready-to-use wrappers:

| Command | Available when | Backend model | Use it for |
|---------|---------------|--------------|------------|
| `claude-deep` | Claude Code installed | `moonshotai/kimi-k2.6` (1T MoE) | Architecture, debugging, refactors, decisions |
| `claude-fast` | Claude Code installed | `qwen/qwen3-next-80b-a3b-instruct` (80B MoE) | HTML/CSS, scripts, fixes, exploration |
| `aider-deep` | Aider installed | `moonshotai/kimi-k2.6` | Same as claude-deep, but via Aider — **no Anthropic account needed** |
| `aider-fast` | Aider installed | `qwen/qwen3-next-80b-a3b-instruct` | Same as claude-fast, via Aider |
| `claude` | (untouched) | Your normal Anthropic plan | When you have tokens, use the real thing |

**Don't have Claude Code or an Anthropic account?** The installer will detect that and offer to install **Aider** instead — an open-source CLI alternative that talks to the same proxy and uses the same NVIDIA backend models. No login, no Anthropic account.

---

## Table of contents

- [Why this exists](#why-this-exists)
- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Linux / macOS](#linux--macos)
  - [Windows](#windows)
  - [For an AI agent installing on your behalf](#for-an-ai-agent-installing-on-your-behalf)
- [Usage](#usage)
- [Configuration](#configuration)
  - [Switching models](#switching-models)
  - [Using a different port](#using-a-different-port)
  - [Inspecting traffic](#inspecting-traffic)
- [Comparison vs Claude plans](#comparison-vs-claude-plans)
- [Caveats & limitations](#caveats--limitations)
- [FAQ](#faq)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Contributing](#contributing)
- [License](#license)

---

## Why this exists

Claude Code is the best agentic coding CLI available, but Anthropic plans have usage caps:

- **Pro ($20/mo)**: ~90 Opus messages per 5 hours
- **Max ($100/mo)**: ~450 Opus messages per 5 hours
- **API**: pay-per-token

When you hit the cap, you wait or pay. NVIDIA offers **free hosted inference** of strong open-weight models (Kimi K2.6, Qwen3-Next, etc.) with ~5,000 credits/month at no cost. This project glues the two together so you can keep working without changing tools or workflow — same `claude` UX, different backend.

**This is a fallback, not a replacement.** Tool-use fidelity for non-Claude models is lower than native Claude. Use the real thing when you can; this for when you can't.

---

## Quick start (for terminal users)

```bash
# 1. Get a free NVIDIA API key
#    → https://build.nvidia.com  (signup is free, key starts with "nvapi-")

# 2. Install
git clone https://github.com/Emaleo0522/claude-fallback-nvidia.git
cd claude-fallback-nvidia
bash linux/install.sh        # Linux/macOS
# or:
powershell -ExecutionPolicy Bypass -File windows\install.ps1   # Windows

# 3. Use (open a new terminal first) — pick the wrappers that match the mode you chose
#    Installed Aider (no Anthropic account required):
aider-deep       # complex tasks  → Kimi K2.6
aider-fast       # routine tasks  → Qwen3-Next 80B
#    Installed Claude Code:
claude-deep      # complex tasks  → Kimi K2.6
claude-fast      # routine tasks  → Qwen3-Next 80B
```

The installer prompts for your API key, detects which CLI you have (or installs Aider for you if you pick mode 2), sets up a local proxy, and tests both routes.

> **No Anthropic account?** When the installer asks "Pick an install mode", press **`2`** (or just Enter — it's the default). You'll get `aider-deep` / `aider-fast` and never need to log in to Anthropic.

---

## Step-by-step install (no terminal experience required)

This guide assumes you've never opened a terminal before. Follow it in order. Don't skip steps.

### What you'll need

- A computer with Linux or Windows.
- About 15 minutes.
- An email address (only for the NVIDIA signup — they don't ask for a credit card).

### Step 1 — Get your free NVIDIA key

1. Open your web browser and go to: **https://build.nvidia.com**
2. Click "Sign up" (top-right) and create a free account with your email.
3. Once logged in, look for "API Keys" in the menu (sometimes under your profile icon).
4. Click "Generate API Key". A long string starting with `nvapi-` will appear.
5. **Copy it.** Save it somewhere safe (like a notes app). You won't see it again after closing the page.

### Step 2 — Open a Terminal

A "terminal" is just an app where you type commands.

**Linux (Mint / Ubuntu / similar):**
- Press the keys `Ctrl` + `Alt` + `T` at the same time.
- A black or dark window will open. That's the terminal.

**Windows:**
- Press the Windows key, type `PowerShell`, and click on "Windows PowerShell".
- A blue window will open. That's PowerShell — the Windows version of a terminal.

### Step 3 — Copy and paste the install commands

> Tip: in a terminal, copy works as `Ctrl+C` and paste is **`Ctrl+Shift+V`** on Linux, or `Ctrl+V` on Windows. You can also right-click and choose "Paste".

Copy the following lines, paste them into your terminal, and press Enter:

**Linux:**
```bash
git clone https://github.com/Emaleo0522/claude-fallback-nvidia.git
cd claude-fallback-nvidia
bash linux/install.sh
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/Emaleo0522/claude-fallback-nvidia.git
cd claude-fallback-nvidia
powershell -ExecutionPolicy Bypass -File windows\install.ps1
```

> If `git` is not installed, the terminal will tell you. Install it from <https://git-scm.com/downloads> and try again.
> If `python3` is not installed, the installer will tell you exactly what to install. Follow its message.

### Step 4 — Answer the installer's questions

The installer will ask a few things. Read each prompt carefully — they're in plain English. Typical flow:

- **"Pick an install mode: 1 / 2 / 3 / 4"** → if you don't have an Anthropic (Claude) account and don't want one, type `2` (Aider) and press Enter. If you do have Claude, type `1`. If unsure, `2` is safe.
- **"NVIDIA_API_KEY:"** → paste the key you saved in Step 1 and press Enter. (Note: the text won't appear as you paste — that's normal, it's hidden for security.)

The installer will then download things, set up the local server, and run two tests. **It can take 2–3 minutes.** Don't close the terminal. You'll see lines starting with `→`, `✓`, and `!`. The end result should be a green message saying `install complete`.

### Step 5 — Use it

**Close** the current terminal and **open a new one** (Step 2 again). This refreshes the system so it sees the new commands.

In the new terminal, type one of the following and press Enter:

- `claude-deep` (if you installed with Claude Code) — for complex tasks
- `claude-fast` (if you installed with Claude Code) — for routine tasks
- `aider-deep` (if you installed with Aider) — for complex tasks
- `aider-fast` (if you installed with Aider) — for routine tasks

You'll get a chat-like prompt where you can describe what you want, just like ChatGPT. The AI is now using free NVIDIA models behind the scenes.

### What if something goes wrong?

| You see | What it means | What to do |
|---------|--------------|------------|
| `git: command not found` | Git isn't installed | Install Git from <https://git-scm.com/downloads> and retry |
| `python3 not found` or `venv module not available` | Python or the venv module is missing | Linux: `sudo apt install python3 python3-venv` then retry. Windows: install Python from <https://python.org> with the "Add to PATH" checkbox |
| `port 4000 is already in use` | Another program is using the same network slot | Restart your computer, then try again |
| `qwen3-next test failed` at the end | Your NVIDIA key is wrong or expired | Repeat Step 1 to get a fresh key, then re-run the installer |
| `command not found: claude-fast` (or aider-fast) | Your terminal hasn't refreshed PATH | Close the terminal completely and open a new one. If still broken, the installer printed a line at the end saying which line to add to your shell config — copy and paste it |

If none of the above match your error, copy the last 20 lines of red/yellow output and open an issue at <https://github.com/Emaleo0522/claude-fallback-nvidia/issues>.

---

## How it works

```
┌─────────────────────────┐
│  claude-deep (wrapper)  │   exports ANTHROPIC_BASE_URL=http://127.0.0.1:4000
│  or claude-fast         │   exports ANTHROPIC_AUTH_TOKEN=sk-litellm-<random>
└──────────┬──────────────┘   exports ANTHROPIC_MODEL=kimi-k2  (or qwen3-next)
           │
           ▼
┌─────────────────────────┐
│  claude (Claude Code)   │   POST /v1/messages   (Anthropic Messages API)
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│  LiteLLM proxy          │   - Translates Anthropic → OpenAI Chat Completions
│  (localhost:4000)       │   - Drops Anthropic-only params (output_config,
│                         │     thinking, cache_control, …)
│                         │   - Routes by model_name (kimi-k2 → kimi-k2.6,
│                         │     qwen3-next → qwen3-next-80b, * → catch-all)
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│  NVIDIA NIM             │   https://integrate.api.nvidia.com/v1/
│  (free-tier inference)  │   - Kimi K2.6  (1T MoE, ~32B active)
│                         │   - Qwen3-Next-80B-A3B  (80B MoE, ~3B active)
└─────────────────────────┘
```

The wrappers (`claude-deep`, `claude-fast`) are thin shell scripts that auto-start the proxy if it's not running, set the right environment variables, then `exec claude`. Claude Code itself is **not** modified — when you run `claude` directly, you still hit Anthropic.

### Augmentations layered on top

The proxy is not a dumb passthrough. It applies three transparent improvements that compensate for the fact that Kimi/Qwen are not as well-calibrated for Claude Code workflows as native Claude is:

1. **System-prompt boost** (`system_boost.md` + `custom_boost.py`). Before each request leaves the proxy, a fixed text is prepended to the system prompt. It contains hard rules — "Read before Edit", "no invented APIs", brevity, Engram protocol, plan-then-execute — that Kimi/Qwen don't apply by default but mostly will when told.
2. **Auto-fallback** (`fallbacks` in `config.yaml`). If `kimi-k2` fails (timeout, NVIDIA `DEGRADED`, 5xx), the proxy retries the same request against `qwen3-next` automatically. The user sees one slightly slower response instead of an error.
3. **Connection warmup** (in `start.sh`). When the proxy launches, it fires one tiny request in the background so the upstream TLS handshake to NVIDIA is paid by the warmup, not by your first real prompt.

Cost note: the boost adds ~1100 input tokens to every request. With NVIDIA free-tier credits at ~5,000/month, that meaningfully shortens your monthly budget but typically pays for itself in fewer retries / better-quality first attempts.

---

## Requirements

Across all platforms:

- **Python 3.10+** with `pip`.
- An **NVIDIA API key** (free) from [build.nvidia.com](https://build.nvidia.com).
- **Internet access** to NVIDIA's API endpoint.
- **At least one CLI client** — either:
  - **Claude Code** ([install](https://docs.anthropic.com/en/docs/claude-code)) — requires an Anthropic account, **OR**
  - **Aider** — open-source, no account needed. The installer will install it for you if missing.

Linux/macOS additional:

- `bash`, `curl`, `python3-venv` (Debian/Ubuntu/Mint: `sudo apt install python3-venv`).
- `pipx` recommended on modern Debian/Ubuntu/Mint (23.04+) so the installer can drop in Aider cleanly: `sudo apt install pipx`.

Windows additional:

- PowerShell 5.1 or newer (Windows 10+ ships this by default).
- Python from [python.org](https://www.python.org/downloads/) with **"Add Python to PATH"** checked at install.
- Recommended alternative: install via [WSL](https://learn.microsoft.com/en-us/windows/wsl/) and follow Linux instructions inside it (more reliable than native PowerShell).

---

## Installation

### Linux / macOS

```bash
git clone https://github.com/Emaleo0522/claude-fallback-nvidia.git
cd claude-fallback-nvidia
bash linux/install.sh
```

The installer is interactive and **adapts to what's on the machine**:

- If both `claude` and `aider` are present → installs all four wrappers.
- If only `claude` is present → installs `claude-deep` / `claude-fast`. Asks if you also want Aider.
- If only `aider` is present → installs `aider-deep` / `aider-fast`. Asks if you want to add Claude Code.
- If **neither** is present → asks you to choose:
  1. Install Claude Code automatically
  2. Install Aider (recommended if you don't want an Anthropic account)
  3. Install both
  4. Just the proxy (you'll bring your own client)

Steps it always runs:

1. Verify base dependencies (`python3`, `python3-venv`, `curl`, free port 4000).
2. Detect any prior install at `~/litellm-proxy/` and ask before overwriting (backs up to `~/litellm-proxy.backup-YYYYMMDD-HHMMSS`).
3. Prompt for your NVIDIA API key (hidden input, must start with `nvapi-`).
4. Create a Python virtualenv at `~/litellm-proxy/.venv` and install LiteLLM.
5. Generate a random master key for the local proxy.
6. Write `~/litellm-proxy/env.sh` (chmod 600) with both keys.
7. Copy proxy templates: `config.yaml`, `start.sh`, `stop.sh`, `custom_boost.py`, `system_boost.md`.
8. Install whichever wrappers apply to `~/.local/bin/`.
9. Start the proxy and run smoke tests against both `qwen3-next` and `kimi-k2`.

If `~/.local/bin` is not in your `PATH`, the installer warns you and shows the line to add to your shell rc file:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

#### Custom install paths

```bash
LITELLM_INSTALL_DIR=/opt/litellm-proxy \
LITELLM_BIN_DIR=/usr/local/bin \
LITELLM_PORT=4001 \
bash linux/install.sh
```

---

### Windows

> **Heads-up:** the Windows installer is best-effort and untested on a real Windows machine. If you hit issues, opening a [WSL](https://learn.microsoft.com/en-us/windows/wsl/) shell and using the Linux installer is the most reliable route.

```powershell
git clone https://github.com/Emaleo0522/claude-fallback-nvidia.git
cd claude-fallback-nvidia
powershell -ExecutionPolicy Bypass -File windows\install.ps1
```

The installer mirrors the Linux flow but uses Windows-native idioms:

- Default `INSTALL_DIR`: `%USERPROFILE%\litellm-proxy`
- Default `BIN_DIR`: `%USERPROFILE%\bin`
- Wrappers are PowerShell scripts: `claude-deep.ps1`, `claude-fast.ps1`
- `env.ps1` is locked down with NTFS ACLs: only the current user can read it
- Background process management uses `Start-Process` with `proxy.pid`

If `%USERPROFILE%\bin` is not in your `PATH`, add it (PowerShell, current user):

```powershell
[Environment]::SetEnvironmentVariable('Path', "$env:Path;$env:USERPROFILE\bin", 'User')
```

---

### For an AI agent installing on your behalf

If you've asked an AI assistant (Claude Code, Aider, Cursor, GPT-based agent, etc.) to install this on a new machine, point it at [`INSTALL_FOR_AI.md`](INSTALL_FOR_AI.md). That file is a structured runbook with explicit pre-flight checks, step-by-step commands, expected outputs, failure modes, and rules about what the agent must *not* do (e.g. never commit your API key, never run sudo without explicit permission).

Sample prompt to give the agent:

> Install [claude-fallback-nvidia](https://github.com/Emaleo0522/claude-fallback-nvidia) on this machine. Read `INSTALL_FOR_AI.md` from the repo, follow it step by step, and ask me for the NVIDIA API key when you reach that step. Report back when each smoke test passes.

---

## Usage

Open a new terminal and pick a wrapper based on the task. Use whichever set was installed on your machine:

**With Claude Code:**
```bash
claude-deep      # complex tasks (Kimi K2.6)
claude-fast      # routine tasks (Qwen3-Next 80B)
claude           # your normal Anthropic plan, untouched
```

**With Aider (no Anthropic account required):**
```bash
aider-deep       # complex tasks (Kimi K2.6)
aider-fast       # routine tasks (Qwen3-Next 80B)
```

Each wrapper auto-starts the proxy if needed, exports the right env vars, then `exec`s the underlying CLI (`claude` or `aider`). Once inside, the CLI works normally — slash commands, file edits, git integration, MCPs (Claude Code), etc.

### Notes on running both backends in the same project

You can have multiple terminals open simultaneously: one running `claude-deep` (Kimi), another `claude-fast` (Qwen3-Next), and a third `claude` (Anthropic). They all read the same files on disk and, if you use [Engram](https://github.com/Emaleo0522/engram-sync) or another shared-memory MCP, they share that state too. There's no conflict — it's just three separate CLI sessions sharing the working tree.

### `/model` inside the session

The `/model` slash command is designed for switching between Anthropic models. With a custom `ANTHROPIC_BASE_URL` it's mostly cosmetic — the proxy's catch-all rule routes any model name to the configured backend. To genuinely switch backends, exit and re-launch with the other wrapper.

---

## Configuration

All configuration lives in `~/litellm-proxy/` (or wherever `LITELLM_INSTALL_DIR` points):

```
~/litellm-proxy/
├── config.yaml      ← model routing rules
├── env.sh           ← NVIDIA_API_KEY, LITELLM_MASTER_KEY, LITELLM_PORT (chmod 600)
├── start.sh         ← starts proxy in background
├── stop.sh          ← stops proxy
├── proxy.pid        ← runtime: current PID
├── proxy.log        ← runtime: stdout+stderr from LiteLLM
└── .venv/           ← Python virtualenv with LiteLLM installed
```

### Switching models

Edit `~/litellm-proxy/config.yaml` and change the `model:` line under `litellm_params`. For example, to swap the deep slot from Kimi K2.6 to Mistral Large 3:

```yaml
- model_name: kimi-k2
  litellm_params:
    model: nvidia_nim/mistralai/mistral-large-3-675b-instruct-2512   # was kimi-k2.6
    api_key: os.environ/NVIDIA_API_KEY
    api_base: https://integrate.api.nvidia.com/v1
    drop_params: true
    additional_drop_params: *anthropic_drop
```

Restart: `~/litellm-proxy/stop.sh && ~/litellm-proxy/start.sh`.

To list every NVIDIA model available with your key:

```bash
source ~/litellm-proxy/env.sh
curl -sS https://integrate.api.nvidia.com/v1/models \
  -H "Authorization: Bearer $NVIDIA_API_KEY" \
  -o /tmp/nvidia-models.json
python3 -c "
import json
data = json.load(open('/tmp/nvidia-models.json'))
for m in sorted(data['data'], key=lambda x: x['id']):
    print(m['id'])
"
```

### Using a different port

Set `LITELLM_PORT` before running the installer:

```bash
LITELLM_PORT=4001 bash linux/install.sh
```

The port is persisted to `env.sh`, so all three (`start.sh`, the wrappers, and the installer's smoke tests) read the same value. To change the port post-install, edit `LITELLM_PORT` in `~/litellm-proxy/env.sh` and restart.

### Inspecting traffic

The proxy logs every request to `~/litellm-proxy/proxy.log`. To watch in real time:

```bash
tail -f ~/litellm-proxy/proxy.log
```

For verbose debugging, edit `config.yaml`:

```yaml
litellm_settings:
  drop_params: true
  set_verbose: true     # was false
```

Restart the proxy after the change.

---

## Comparison vs Claude plans

| Plan | Cost | Capacity (post May 2026 update) | Best for |
|------|-----:|-------------------------------|----------|
| **NVIDIA free tier** (this project) | $0 | ~5,000 credits/month, no SLA, shared GPUs | Fallback when paid plan exhausted, prototyping |
| **Claude Pro** | $20/mo | ~90 Opus msgs / 5h, no peak throttling | Daily light–medium use |
| **Claude Max** | $100/mo | ~450 Opus msgs / 5h | Heavy daily use, multiple projects |
| **Claude API** | per-token | Tier 1: 1M+ tokens/min after May '26 boost | Production apps, batch jobs |

Quality ranking for agentic coding (rough):

```
Claude Opus 4.7  >  Claude Sonnet 4.6  >  Kimi K2.6  >  Qwen3-Next 80B  >  Llama 3.3 70B
   (real)             (real)            (this proj)     (this proj)         (e.g. Groq)
```

Tool-use fidelity in Claude Code follows the same ordering. Expect more occasional "the model used the wrong tool" or "ignored a system instruction" with Kimi/Qwen than with native Claude. That's the cost of free.

---

## Caveats & limitations

This project is **beta** and **opinionated**. The honest list:

- **NVIDIA free tier is preview infrastructure.** Models can be deprecated, rate-limited, or briefly unavailable without notice. We've already seen `kimi-k2-thinking`, `kimi-k2-instruct`, and `devstral-2-123b` go through churn during development.
- **Latency is higher** than Anthropic, especially from outside the US. Expect 200–500ms per request just on the network round-trip, plus cold-start queues on shared GPUs.
- **Tool-use fidelity is lower.** Claude Code is calibrated for Anthropic models. Kimi and Qwen handle tool calls but with more drift, occasional malformed `tool_use` blocks, or skipped steps.
- **Context window**: 256K tokens for both models — large, but smaller than Opus 4.7's 1M-token window.
- **No prompt caching.** Each turn re-sends the full conversation. Long sessions get slow.
- **Free tier is not for production.** If you build a webapp that calls these endpoints, you'll exhaust 5,000 credits/month quickly. For prod, use NVIDIA paid tier, [Groq](https://groq.com), [OpenRouter](https://openrouter.ai), or self-host.
- **Windows installer is untested on real Windows.** PRs welcome from anyone who runs it natively.
- **No autostart on boot.** The proxy starts when a wrapper detects it's down. If you want systemd / Task Scheduler integration, write your own service file (PRs also welcome).

---

## FAQ

### Does this expose my NVIDIA API key?

No. The key lives in `~/litellm-proxy/env.sh` (chmod 600) — readable only by you. It's never sent anywhere except NVIDIA's API. The local proxy is bound to `127.0.0.1` (loopback only), not exposed to the network.

### Will this break my normal `claude` command?

No. The wrappers are separate binaries (`claude-deep`, `claude-fast`). When you type `claude`, nothing about it changes — same Anthropic auth, same model, same UI.

### Can I use this with Aider, Cursor, OpenCode, or other CLI tools?

Yes. The proxy speaks both Anthropic's `/v1/messages` (used by Claude Code) and OpenAI-compatible `/v1/chat/completions`. Point any client at `http://127.0.0.1:4000` with the master key from `env.sh`. Example for Aider:

```bash
source ~/litellm-proxy/env.sh
export OPENAI_API_BASE=http://127.0.0.1:4000
export OPENAI_API_KEY="$LITELLM_MASTER_KEY"
aider --model openai/kimi-k2
```

### Why don't you support Groq / OpenRouter / Together / etc?

You can — LiteLLM supports them all. This repo just ships NVIDIA defaults because that's where the strongest free-tier coding models (Kimi K2.6, Qwen3-Next 80B) currently live. To add Groq, append a model entry to `config.yaml` with `model: groq/llama-3.3-70b-versatile` and the right API key. PRs adding multi-provider configs are welcome.

### Does this work with MCP servers?

Yes. MCPs are configured in `~/.claude/settings.json` and live in Claude Code itself, not in the proxy. Whatever MCPs you have configured (Engram, Playwright, Supabase, etc.) keep working with `claude-deep` and `claude-fast` exactly like they do with `claude`.

### What happens if NVIDIA deprecates the model I'm using?

You'll start getting `Function id ... DEGRADED cannot be invoked` errors. Edit `config.yaml`, swap to a different model id, restart the proxy. See [`docs/troubleshooting.md`](docs/troubleshooting.md) for a list of currently-known deprecations.

### Can I run the proxy on my VPS instead of localhost?

Yes, but only if you put proper auth in front of it (the master key is meant for localhost loopback, not internet exposure). For a VPS deployment, change the bind in `start.sh` to `--host 0.0.0.0`, put nginx in front with TLS + IP allowlist, and rotate the master key regularly. Out of scope for this project's defaults.

---

## Troubleshooting

Common errors and their fixes are documented in [`docs/troubleshooting.md`](docs/troubleshooting.md):

- `BadRequestError: Unsupported parameter X` → drop the param in config
- `Function id ... DEGRADED` → model deprecated, swap it
- `port 4000 already in use` → set `LITELLM_PORT`
- Tool calls fail / Claude seems "lost" → ordinary friction, sometimes fall back to real `claude`
- First call hangs > 60s → free tier queue, retry

If your problem isn't listed, open an [issue](https://github.com/Emaleo0522/claude-fallback-nvidia/issues) with:

1. The exact command you ran
2. Last 30 lines of `~/litellm-proxy/proxy.log`
3. OS and Python version (`python3 --version`)
4. Output of `~/litellm-proxy/.venv/bin/litellm --version`

---

## Uninstall

### Linux / macOS

```bash
cd claude-fallback-nvidia
bash linux/uninstall.sh
```

It stops the proxy, asks before removing `~/litellm-proxy/`, and asks before removing the wrappers. Nothing is deleted without confirmation.

### Windows

```powershell
cd claude-fallback-nvidia
powershell -ExecutionPolicy Bypass -File windows\uninstall.ps1
```

---

## Contributing

Issues and PRs welcome, especially:

- **Windows fixes** — the installer needs real-world testing.
- **Multi-provider configs** — example `config.yaml` for Groq, OpenRouter, Together, etc.
- **Better failure detection** — e.g. detecting model deprecation at startup and warning the user.
- **macOS specifics** — path conventions, Homebrew Python interactions.

When opening a PR, please:

1. Don't commit secrets or your personal `env.sh`.
2. Test the Linux installer end-to-end if you change the install flow.
3. Update `INSTALL_FOR_AI.md` if you change steps an agent would execute.
4. Update `docs/troubleshooting.md` if you've hit a new failure mode in the wild.

---

## License

[MIT](LICENSE) © 2026 [Emaleo0522](https://github.com/Emaleo0522)

This project is not affiliated with Anthropic or NVIDIA. "Claude" and "Claude Code" are trademarks of Anthropic. "NVIDIA NIM" is a trademark of NVIDIA Corporation.
