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
if [ -n "${DISPLAY:-}" ] && command -v setxkbmap >/dev/null 2>&1; then
  setxkbmap -layout "$KEYBOARD_LAYOUT" -option "$XKB_OPTIONS" 2>/dev/null || true
fi

# Prefer a writable user data dir under HOME (works with x11docker --home)
USER_DATA_DIR="${CHROMIUM_USER_DATA_DIR:-$HOME/.config/chromium}"
mkdir -p "$USER_DATA_DIR" "$HOME/Downloads" \
  "${XDG_CACHE_HOME:-$HOME/.cache}/chromium" \
  "$HOME/.pki" 2>/dev/null || true

# Sandbox policy
# ----------------
# Prefer Chromium's *namespace* sandbox (not --no-sandbox).
# Needs:
#   1) unprivileged user namespaces on the host
#   2) seccomp that allows clone/unshare/setns/chroot without CAP_SYS_ADMIN
#      (seccomp/chromium.json via run-x11docker.sh)
#
# Do NOT pass --disable-setuid-sandbox in the normal path: it is unnecessary
# when the namespace sandbox works, and Chromium shows a yellow infobar
# ("unsupported command-line flag: --disable-setuid-sandbox"). Under x11docker
# (cap-drop=ALL, no-new-privileges) the setuid helper cannot elevate anyway;
# if chrome-sandbox is missing or inert, Chromium uses the namespace sandbox.
#
# Set CHROMIUM_NO_SANDBOX=1 only as a last resort (container is then the sole
# sandbox — same as many stock "docker chromium" recipes, and weaker).
SANDBOX_FLAGS=()
if [ "${CHROMIUM_NO_SANDBOX:-0}" = "1" ]; then
  echo "WARNING: CHROMIUM_NO_SANDBOX=1 — Chromium process sandbox disabled" >&2
  SANDBOX_FLAGS+=(--no-sandbox --disable-setuid-sandbox)
fi

# --disable-dev-shm-usage: avoid crashes when /dev/shm is the default 64MiB.
# Prefer also passing --shm-size=1g to docker/x11docker when possible.
exec chromium \
  "${SANDBOX_FLAGS[@]}" \
  --disable-dev-shm-usage \
  --user-data-dir="$USER_DATA_DIR" \
  --no-first-run \
  --no-default-browser-check \
  "$@"
