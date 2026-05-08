# Troubleshooting

## Common errors

### `BadRequestError: Unsupported parameter(s): X`

NVIDIA's OpenAI-compatible endpoint rejects an Anthropic-only param. Add the param name to `additional_drop_params` in `~/litellm-proxy/config.yaml` and restart the proxy.

```yaml
_anthropic_drop: &anthropic_drop
  - output_config
  - cache_control
  - thinking
  - metadata
  - anthropic_beta
  - anthropic_version
  - service_tier
  - YOUR_NEW_PARAM_HERE
```

```bash
~/litellm-proxy/stop.sh && ~/litellm-proxy/start.sh
```

### `Function id ... DEGRADED cannot be invoked`

NVIDIA disabled this model. Pick another from <https://build.nvidia.com/models> and update `config.yaml`. After we shipped this repo, we already saw it happen with:
- `kimi-k2-thinking` (deprecated 2026-05-12 — replaced with `kimi-k2.6`)
- `kimi-k2-instruct` (same date)
- `qwen3.5-122b-a10b` (DEGRADED)
- `devstral-2-123b-instruct-2512` (DEGRADED)

### Proxy hangs / first request times out > 60s

NVIDIA free tier shares GPUs across all users. When demand spikes you go into a queue. There's no SLA. Retry, or switch to the lighter model:

```bash
# inside config.yaml, swap kimi-k2 to point at qwen3-next as a fallback
```

### `port 4000 already in use`

Another process bound it. Either free it or pick a new port:

```bash
LITELLM_PORT=4001 bash linux/install.sh   # only works on a fresh install
```

For an existing install, edit `start.sh` and the wrappers manually to use the new port.

### `claude-deep / claude-fast: command not found`

Your `~/.local/bin` (Linux) or `%USERPROFILE%\bin` (Windows) is not in PATH. Add it:

```bash
# Linux — append to ~/.bashrc or ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"
```

```powershell
# Windows — PowerShell, current user
[Environment]::SetEnvironmentVariable('Path', "$env:Path;$env:USERPROFILE\bin", 'User')
```

Open a new terminal after.

### Tool calls fail / Claude Code seems "lost"

This is the cost of running Claude Code against a non-Claude model. Qwen and Kimi handle tool use but with lower fidelity than Claude itself. Workarounds:

- Be more explicit in prompts: tell the model exactly which tool to use.
- Break large tasks into smaller steps.
- For agentic workflows that hit lots of tool errors, fall back to plain `claude`.

### Free tier exhausted

NVIDIA free tier is ~5000 credits/month. When it runs out:

- Wait until the next billing cycle.
- Add a credit card to NVIDIA for paid tier.
- Switch provider — see README on alternatives (Groq, OpenRouter).

## Inspecting traffic

The proxy logs every request and response to `~/litellm-proxy/proxy.log`:

```bash
tail -f ~/litellm-proxy/proxy.log
```

To enable verbose logging, edit `config.yaml`:

```yaml
litellm_settings:
  set_verbose: true
```

Then restart the proxy.

## Manually testing the proxy

Use plain curl to bypass Claude Code and confirm the proxy works:

```bash
source ~/litellm-proxy/env.sh
curl -sS -X POST http://127.0.0.1:4000/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: $LITELLM_MASTER_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"qwen3-next","max_tokens":40,"messages":[{"role":"user","content":"hi"}]}'
```

If this works but `claude-fast` doesn't, the bug is in the wrapper or in Claude Code's request shape — check the proxy log for the actual request body Claude sent.

## Switching to a different NVIDIA model

Edit `~/litellm-proxy/config.yaml`. Find the entry for `kimi-k2` or `qwen3-next` and change the `model:` line under `litellm_params`:

```yaml
- model_name: kimi-k2
  litellm_params:
    model: nvidia_nim/SOME_OTHER_MODEL_HERE   # <-- change this
    api_key: os.environ/NVIDIA_API_KEY
    api_base: https://integrate.api.nvidia.com/v1
```

Get the full list of available model IDs:

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

Restart the proxy after editing.
