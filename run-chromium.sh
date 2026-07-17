#!/usr/bin/env bash
set -euo pipefail

# Ensure HOME is set (x11docker does this, but be defensive)
if [ -z "${HOME:-}" ]; then
  echo "ERROR: HOME is not set" >&2
  exit 1
fi

# Optional keyboard layout (same idea as x11docker-cursor)
: "${KEYBOARD_LAYOUT:=us}"
: "${XKB_OPTIONS:=lv3:ralt_switch}"
if command -v setxkbmap >/dev/null 2>&1; then
  setxkbmap -layout "$KEYBOARD_LAYOUT" -option "$XKB_OPTIONS" || true
fi

# Prefer a writable user data dir under HOME (works with x11docker --home)
USER_DATA_DIR="${CHROMIUM_USER_DATA_DIR:-$HOME/.config/chromium}"
mkdir -p "$USER_DATA_DIR" "$HOME/Downloads"

# Container / x11docker-friendly flags:
# - --no-sandbox / --disable-setuid-sandbox: x11docker drops capabilities and
#   uses no-new-privileges; Chromium's setuid sandbox will not work. The
#   container itself is the sandbox.
# - --disable-dev-shm-usage: avoid crashes when /dev/shm is the default 64MiB.
#   Prefer also passing --shm-size=1g to docker/x11docker when possible.
exec chromium \
  --no-sandbox \
  --disable-setuid-sandbox \
  --disable-dev-shm-usage \
  --user-data-dir="$USER_DATA_DIR" \
  --no-first-run \
  --no-default-browser-check \
  "$@"
