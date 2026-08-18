#!/usr/bin/env bash
# Hardened launcher for this image via x11docker.
# Inspired by: https://medium.com/code-and-coffee/running-chromium-in-docker-without-selling-your-soul-433e591802f2
#
# Goals:
#   - Keep Chromium's own sandbox (custom seccomp, no CAP_SYS_ADMIN)
#   - Keep x11docker defaults: cap-drop=ALL, no-new-privileges, nested X
#   - Add resource limits and safer clipboard defaults
#
# Usage:
#   ./run-x11docker.sh [extra x11docker args...] [-- chromium args...]
#   ./run-x11docker.sh --home --share "$HOME/Downloads"
#   CHROMIUM_NO_SANDBOX=1 ./run-x11docker.sh   # emergency fallback only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECCOMP_PROFILE="${SECCOMP_PROFILE:-$SCRIPT_DIR/seccomp/chromium.json}"
IMAGE="${X11DOCKER_CHROMIUM_IMAGE:-chromium}"
SHM_SIZE="${SHM_SIZE:-1g}"
PIDS_LIMIT="${PIDS_LIMIT:-512}"

if ! command -v x11docker >/dev/null 2>&1; then
  echo "ERROR: x11docker not found in PATH" >&2
  echo "Install: https://github.com/mviereck/x11docker" >&2
  exit 1
fi

# Allow disabling custom seccomp for diagnosis:
#   SECCOMP_PROFILE=unconfined ./run-x11docker.sh --home
#   SECCOMP=0 ./run-x11docker.sh --home
DOCKER_SECCOMP_OPT=()
if [ "${SECCOMP:-1}" = "0" ] || [ "${SECCOMP_PROFILE}" = "unconfined" ] || [ "${SECCOMP_PROFILE}" = "0" ]; then
  echo "WARNING: running with seccomp=unconfined (diagnosis only)" >&2
  DOCKER_SECCOMP_OPT=(--security-opt seccomp=unconfined)
else
  if [ ! -f "$SECCOMP_PROFILE" ]; then
    echo "ERROR: seccomp profile not found: $SECCOMP_PROFILE" >&2
    exit 1
  fi
  # x11docker runs PID1 as: env docker-init -- /bin/sh - containerrc
  # Debian dash uses vfork/fork for every external command. A trimmed profile
  # without fork/vfork makes containerrc exit instantly → x11docker error
  # "Did not receive PID of PID1". The image ENTRYPOINT is NOT used here.
  if ! grep -q '"fork"' "$SECCOMP_PROFILE" || ! grep -q '"vfork"' "$SECCOMP_PROFILE"; then
    echo "ERROR: seccomp profile is missing fork/vfork: $SECCOMP_PROFILE" >&2
    echo "  x11docker PID1 is /bin/sh (dash), which needs fork/vfork." >&2
    echo "  Sync the latest seccomp/chromium.json (commit ce02992+), or run:" >&2
    echo "    SECCOMP_PROFILE=unconfined ./run-x11docker.sh --home" >&2
    exit 1
  fi
  DOCKER_SECCOMP_OPT=(--security-opt "seccomp=$SECCOMP_PROFILE")
fi

# Split args at first bare "--" that starts chromium/image options for the user.
# Everything we add for docker goes after x11docker's "--" separator.
USER_X11DOCKER_ARGS=()
USER_AFTER=()
seen_ddash=0
for arg in "$@"; do
  if [ "$seen_ddash" -eq 0 ] && [ "$arg" = "--" ]; then
    seen_ddash=1
    continue
  fi
  if [ "$seen_ddash" -eq 1 ]; then
    USER_AFTER+=("$arg")
  else
    USER_X11DOCKER_ARGS+=("$arg")
  fi
done

# Base x11docker options (caller can override/add via args)
# --network: browser needs outbound network (Docker default bridge)
# --clipboard=c2h: container→host only (safer than full bidirectional)
# --limit: optional CPU/RAM cap (~50% free). Off by default: software
#          rendering without --gpu is already heavy; enable with LIMIT=1.
X11DOCKER_BASE=(
  --network
  --clipboard=c2h
)
if [ "${LIMIT:-0}" = "1" ]; then
  X11DOCKER_BASE+=(--limit)
fi

# Docker run options after x11docker's "--"
# - seccomp: allow Chromium namespace sandbox without SYS_ADMIN
# - pids-limit: mitigate fork bombs
# - shm-size: Chromium needs more than Docker's 64MiB default
DOCKER_OPTS=(
  --shm-size="$SHM_SIZE"
  --pids-limit="$PIDS_LIMIT"
  "${DOCKER_SECCOMP_OPT[@]}"
)

# Optional read-only rootfs (extra tmpfs for writable paths Chromium needs).
# Enable with: READ_ONLY=1 ./run-x11docker.sh
# Prefer combining with --home so the profile lives on a writable volume.
if [ "${READ_ONLY:-0}" = "1" ]; then
  DOCKER_OPTS+=(
    --read-only
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=256m
    --tmpfs /var/tmp:rw,noexec,nosuid,nodev,size=64m
    --tmpfs /run:rw,noexec,nosuid,nodev,size=64m
  )
fi

# Pass through CHROMIUM_NO_SANDBOX if set
ENV_OPTS=()
if [ "${CHROMIUM_NO_SANDBOX:-0}" = "1" ]; then
  ENV_OPTS+=(-e CHROMIUM_NO_SANDBOX=1)
fi

if [ "${KEYBOARD_LAYOUT:-}" != "" ]; then
  ENV_OPTS+=(-e "KEYBOARD_LAYOUT=$KEYBOARD_LAYOUT")
fi

if [ "${DEBUG:-0}" = "1" ]; then
  set -x
fi

exec x11docker \
  "${X11DOCKER_BASE[@]}" \
  "${USER_X11DOCKER_ARGS[@]}" \
  -- \
  "${DOCKER_OPTS[@]}" \
  "${ENV_OPTS[@]}" \
  -- \
  "$IMAGE" \
  "${USER_AFTER[@]}"
