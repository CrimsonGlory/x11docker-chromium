#!/usr/bin/env bash
# Reproduce x11docker's PID1 shape and print the real failure (not hidden by x11docker).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECCOMP_PROFILE="${SECCOMP_PROFILE:-$SCRIPT_DIR/seccomp/chromium.json}"
IMAGE="${X11DOCKER_CHROMIUM_IMAGE:-chromium}"

echo "== profile =="
ls -la "$SECCOMP_PROFILE"
grep -E '"fork"|"vfork"' "$SECCOMP_PROFILE" || echo "MISSING fork/vfork"

INIT=""
for c in /usr/bin/catatonit /usr/libexec/docker/docker-init /usr/bin/docker-init /usr/bin/tini-static; do
  [ -x "$c" ] && INIT="$c" && break
done
if [ -z "$INIT" ]; then
  echo "ERROR: no docker-init/tini found on host" >&2
  exit 1
fi
echo "== init =="
ls -la "$INIT"

SHARE=$(mktemp -d)
trap 'rm -rf "$SHARE"' EXIT
cat > "$SHARE/containerrc" << 'EOF'
#! /bin/sh
echo CONTAINERRC_START
id
uname -m
echo CONTAINERRC_OK
EOF

echo "== docker run (x11docker-like) =="
set +e
docker run --rm \
  --shm-size=3g --pids-limit=4096 \
  --security-opt "seccomp=$SECCOMP_PROFILE" \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --entrypoint env \
  -v "$SHARE:/x11docker" \
  -v "$INIT:/usr/bin/docker-init:ro" \
  "$IMAGE" \
  /usr/bin/docker-init -g -- /bin/sh - /x11docker/containerrc
rc=$?
set -e
echo "exit=$rc"
if [ "$rc" -ne 0 ]; then
  echo
  echo "If you saw 'Cannot fork' or 'failed to create signalfd', sync seccomp/chromium.json (needs fork/vfork/signalfd/signalfd4)."
fi
exit "$rc"
