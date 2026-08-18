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
#   2) seccomp that allows clone/unshare/chroot without CAP_SYS_ADMIN
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

# Graphics
# --------
# Nested X (Xephyr/nxagent/etc.) often exposes only ancient GLX. Chromium then
# fails eglInitialize ("Unsupported GLX version (requires at least 1.3)"),
# kills the GPU process, and restarts it in a loop — that is the main source of
# lag without x11docker --gpu.
#
# With /dev/dri (x11docker --gpu): keep hardware GL, ignore blocklist.
# Without DRI: skip the GPU process and use software compositing from the start.
#
# Override:
#   CHROMIUM_GPU=0     force software even if DRI is present
#   CHROMIUM_GPU=1     force hardware path even if DRI is missing
#   CHROMIUM_GPU=auto  (default) detect /dev/dri
#
# Avoid external `ls` (needs fork under tight seccomp); use bash globs only.
GPU_FLAGS=()
has_dri=0
for p in /dev/dri/renderD128 /dev/dri/card0 /dev/dri/renderD* /dev/dri/card*; do
  if [ -e "$p" ]; then
    has_dri=1
    break
  fi
done
case "${CHROMIUM_GPU:-auto}" in
  1|yes|true|on|hardware)
    has_dri=1
    ;;
  0|no|false|off|software)
    has_dri=0
    ;;
esac
if [ "$has_dri" -eq 1 ]; then
  GPU_FLAGS+=(
    --ignore-gpu-blocklist
    --enable-gpu-rasterization
  )
else
  # Avoid GPU-process crash thrash on nested X without GL.
  GPU_FLAGS+=(
    --disable-gpu
    --disable-gpu-compositing
  )
fi

# Shared memory
# -------------
# Docker's default /dev/shm is 64MiB and crashes Chromium; run-x11docker.sh
# raises it with --shm-size=1g. Trust that by default. Force disk-backed
# shmem only when explicitly requested (do not `df|awk` here — pipes need fork).
SHM_FLAGS=()
if [ "${CHROMIUM_DISABLE_DEV_SHM:-0}" = "1" ]; then
  SHM_FLAGS+=(--disable-dev-shm-usage)
fi

# Binary
# ------
# Debian ships /usr/bin/chromium as a *shell script* that forks for
# `uname` / pipelines before exec'ing the ELF. Under a tight outer seccomp
# that historically omitted fork, that aborts with "Cannot fork" and x11docker
# reports "Did not receive PID of PID1". Prefer the ELF directly.
CHROMIUM_BIN="${CHROMIUM_BIN:-/usr/lib/chromium/chromium}"
if [ ! -x "$CHROMIUM_BIN" ]; then
  CHROMIUM_BIN="$(command -v chromium || true)"
fi
if [ -z "$CHROMIUM_BIN" ] || [ ! -x "$CHROMIUM_BIN" ]; then
  echo "ERROR: Chromium binary not found" >&2
  exit 1
fi

# Optional Debian distro flags from /etc/chromium.d (sourced; no subshell).
CHROMIUM_FLAGS="${CHROMIUM_FLAGS:-}"
if [ -d /etc/chromium.d ]; then
  for file in /etc/chromium.d/*; do
    [ -f "$file" ] || continue
    case "$file" in
      *.dpkg*) continue ;;
      */README) continue ;;
    esac
    # shellcheck disable=SC1090
    . "$file" || true
  done
fi

# shellcheck disable=SC2086
exec "$CHROMIUM_BIN" \
  ${CHROMIUM_FLAGS} \
  "${SANDBOX_FLAGS[@]}" \
  "${GPU_FLAGS[@]}" \
  "${SHM_FLAGS[@]}" \
  --user-data-dir="$USER_DATA_DIR" \
  --no-first-run \
  --no-default-browser-check \
  "$@"
