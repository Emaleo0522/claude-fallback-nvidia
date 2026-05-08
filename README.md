# claude-fallback-nvidia

Local LiteLLM proxy + wrappers that route Claude Code to NVIDIA's free inference API. Lets you keep using `claude` (the CLI) when your Claude Pro/Max tokens run out, by transparently swapping the backend to free-tier models hosted on NVIDIA NIM.

## What you get

After installing, three new commands sit alongside your existing `claude`:

| Command | Backend model | Use for |
|---------|---------------|---------|
| `claude-deep` | Kimi K2.6 (1T MoE) | Complex tasks: architecture, refactors, debugging |
| `claude-fast` | Qwen3-Next 80B (MoE, ~3B active) | Routine tasks: HTML/CSS, scripts, small fixes |
| `claude` (untouched) | Whatever your Anthropic plan provides | Best quality when tokens are available |

## Requirements

- An NVIDIA API key from <https://build.nvidia.com> (free, gives ~5000 credits/month)
- Claude Code already installed (`claude` available in PATH)
- Python 3.10+
- Linux: `python3-venv`, `curl`, `bash`. Windows: PowerShell 5.1+, Python from python.org with PATH enabled

## Install

### Linux

```bash
git clone https://github.com/Emaleo0522/claude-fallback-nvidia.git
cd claude-fallback-nvidia
bash linux/install.sh
```

The installer will:
1. Ask for your NVIDIA API key
2. Create `~/litellm-proxy/` with venv + LiteLLM
3. Install `claude-deep` and `claude-fast` into `~/.local/bin/`
4. Start the proxy in background
5. Test the routes

### Windows

> Best-effort. WSL is more reliable. Native PowerShell path:

```powershell
git clone https://github.com/Emaleo0522/claude-fallback-nvidia.git
cd claude-fallback-nvidia
powershell -ExecutionPolicy Bypass -File windows\install.ps1
```

## How it works

```
claude-deep / claude-fast (wrappers)
        │
        │ exports ANTHROPIC_BASE_URL=http://127.0.0.1:4000
        │ exports ANTHROPIC_AUTH_TOKEN=sk-litellm-<random>
        ▼
   claude (Claude Code CLI)
        │
        │ POST /v1/messages  (Anthropic format)
        ▼
   LiteLLM proxy (localhost:4000)
        │
        │ translates Anthropic → OpenAI format,
        │ drops Anthropic-only params (output_config, thinking, …)
        ▼
   NVIDIA NIM (https://integrate.api.nvidia.com/v1/chat/completions)
   → moonshotai/kimi-k2.6  or  qwen/qwen3-next-80b-a3b-instruct
```

## What gets installed

| Path | What |
|------|------|
| `~/litellm-proxy/` | Proxy installation: config, venv, scripts, logs |
| `~/.local/bin/claude-deep` | Wrapper that launches `claude` against Kimi K2.6 |
| `~/.local/bin/claude-fast` | Wrapper that launches `claude` against Qwen3-Next |
| `~/litellm-proxy/env.sh` | Your NVIDIA key + a generated master key (chmod 600) |

Nothing global is touched. To remove: `bash linux/uninstall.sh`.

## Caveats

- NVIDIA free tier is **preview** infrastructure. Models can be deprecated or rate-limited without warning.
- Tool-use fidelity for non-Claude models in Claude Code is lower than native Claude. Expect occasional misuse of `Read`/`Edit`/`Bash`.
- Latency from Argentina/EU to NVIDIA US endpoints adds ~150-300ms per request.
- Free tier is **not** suitable for production webapps — for that you need NVIDIA paid tier or a different provider (e.g. Groq).

## Files for AI assistants

If you're an AI agent and you've been asked to install this on a new machine, read [`INSTALL_FOR_AI.md`](INSTALL_FOR_AI.md) — it has explicit step-by-step instructions safe to execute.

## License

MIT
