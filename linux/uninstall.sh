#!/usr/bin/env bash
# Remove claude-fallback-nvidia. Asks before deleting anything.
set -euo pipefail

INSTALL_DIR="${LITELLM_INSTALL_DIR:-$HOME/litellm-proxy}"
BIN_DIR="${LITELLM_BIN_DIR:-$HOME/.local/bin}"

echo "claude-fallback-nvidia uninstaller"
echo "  install dir: $INSTALL_DIR"
echo "  bin dir:     $BIN_DIR"
echo

# Stop proxy if running
if [[ -x "$INSTALL_DIR/stop.sh" ]]; then
  echo "stopping proxy..."
  "$INSTALL_DIR/stop.sh" || true
fi

read -r -p "Remove $INSTALL_DIR ? [y/N] " ans
if [[ "${ans,,}" =~ ^y(es)?$ ]]; then
  rm -rf "$INSTALL_DIR"
  echo "removed $INSTALL_DIR"
fi

read -r -p "Remove wrappers ($BIN_DIR/claude-deep, $BIN_DIR/claude-fast)? [y/N] " ans
if [[ "${ans,,}" =~ ^y(es)?$ ]]; then
  rm -f "$BIN_DIR/claude-deep" "$BIN_DIR/claude-fast"
  echo "removed wrappers"
fi

echo "done."
