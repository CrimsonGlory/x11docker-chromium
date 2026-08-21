#!/bin/bash
# Script to copy the host clipboard inside the container. xclip is needed.
# If you don't like bidirectional clipboard with non-free software for security
# reasons, then this script will help with copy from outside cursor to inside.
# This has to be executed outside the container obviously.
#
set -e

if ! command -v xclip >/dev/null 2>&1; then
  echo "Error: xclip is not installed on the host"
  exit 1
fi

CONTAINER_ID=$(docker ps --format "{{.ID}}\t{{.Names}}" \
  | grep -E "x11docker_X[0-9]+_chromium" \
  | grep -Eo "^[a-f0-9]+" \
  | tr -d "\n")

if [ -z "$CONTAINER_ID" ]; then
  echo "Unable to obtain container id."
  exit 1
fi

xclip -selection clipboard -o | docker exec -i "$CONTAINER_ID" xclip -selection clipboard

echo -e "Clipboard copied to container $CONTAINER_ID."

