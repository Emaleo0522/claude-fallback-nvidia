#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f proxy.pid ]]; then
  PID=$(cat proxy.pid)
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" && echo "stopped PID=$PID"
  else
    echo "PID $PID not running"
  fi
  rm -f proxy.pid
else
  pkill -f "litellm.*$(pwd)/config.yaml" && echo "stopped via pkill" || echo "nothing to stop"
fi
