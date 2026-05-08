#!/usr/bin/env bash
# Start the LiteLLM proxy in the background. Idempotent.
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

PORT="${LITELLM_PORT:-4000}"
HOST="${LITELLM_HOST:-127.0.0.1}"

if pgrep -f "litellm.*--config.*$(pwd)/config.yaml" >/dev/null; then
  echo "litellm proxy already running. PID(s): $(pgrep -f "litellm.*$(pwd)/config.yaml" | tr '\n' ' ')"
  exit 0
fi

# Make custom_boost.py importable as a module (LiteLLM's callbacks string
# resolves through sys.path, which doesn't include cwd by default).
export PYTHONPATH="$(pwd):${PYTHONPATH:-}"

nohup ./.venv/bin/litellm \
  --config ./config.yaml \
  --port "$PORT" --host "$HOST" \
  > proxy.log 2>&1 &

PID=$!
echo $PID > proxy.pid

sleep 2
if ! kill -0 "$PID" 2>/dev/null; then
  echo "FAILED to start. Last 20 lines of proxy.log:"
  tail -20 proxy.log
  exit 1
fi
echo "litellm proxy started. PID=$PID  URL=http://$HOST:$PORT  log=$(pwd)/proxy.log"

# ─── Connection warmup (async) ─────────────────────────────────────────────
# Wait until the HTTP server is responsive, then fire a tiny request so the
# upstream TLS handshake to NVIDIA is paid by the warmup, not by the user's
# first real prompt.
(
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS --max-time 1 "http://$HOST:$PORT/health/liveness" >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done
  curl -fsS --max-time 30 \
    -X POST "http://$HOST:$PORT/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $LITELLM_MASTER_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"qwen3-next","max_tokens":1,"messages":[{"role":"user","content":"ok"}]}' \
    >/dev/null 2>&1 || true
) >/dev/null 2>&1 &
disown $! 2>/dev/null || true
echo "warmup dispatched in background"
