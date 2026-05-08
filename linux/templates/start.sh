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

nohup ./.venv/bin/litellm \
  --config ./config.yaml \
  --port "$PORT" --host "$HOST" \
  > proxy.log 2>&1 &

PID=$!
echo $PID > proxy.pid

sleep 2
if kill -0 "$PID" 2>/dev/null; then
  echo "litellm proxy started. PID=$PID  URL=http://$HOST:$PORT  log=$(pwd)/proxy.log"
else
  echo "FAILED to start. Last 20 lines of proxy.log:"
  tail -20 proxy.log
  exit 1
fi
