#!/usr/bin/env bash
# Build the agent task image (OpenCode, rtk, Engram, Graphify) and push it to a throwaway registry on the kind network.
# `ax local` creates no registry, and the atelet pulls task images itself, so we run registry:2
# attached to the "kind" network and reference it by private IP (go-containerregistry uses plain
# HTTP for RFC1918 addresses). AX needs images pinned by digest; it's written to the env file.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CTX="$HERE/image"
BASE=${BASE_IMAGE:-docker.io/library/node:22-slim}
REG_NAME=ax-registry

if ! podman ps --format '{{.Names}}' | grep -qx "$REG_NAME"; then
  podman rm -f "$REG_NAME" >/dev/null 2>&1 || true
  podman run -d --name "$REG_NAME" --network kind --restart=always docker.io/library/registry:2 >/dev/null
fi
REG_IP=$(podman inspect "$REG_NAME" --format '{{(index .NetworkSettings.Networks "kind").IPAddress}}')
REG="$REG_IP:5000"
NAME=${IMAGE_NAME:-opencode-task}
ENVVAR=${ENV_VAR:-OPENCODE_IMAGE}
ENVFILE=${ENV_FILE:-.env.opencode}
IMG="$REG/$NAME:dev"
echo "registry: $REG"

podman build --build-arg BASE_IMAGE="$BASE" \
  -f "$CTX/Dockerfile" -t "$IMG" "$CTX"
# The push runs inside the podman VM, whose proxy env must exclude the registry IP.
podman machine ssh "sudo env NO_PROXY=$REG_IP no_proxy=$REG_IP podman push --tls-verify=false --digestfile /tmp/$NAME.digest $IMG"

DIGEST=$(podman machine ssh "cat /tmp/$NAME.digest" | tail -1)
[ -n "$DIGEST" ] || { echo "could not resolve digest for $IMG"; exit 1; }
echo "$ENVVAR=$REG/$NAME@$DIGEST" > "$HERE/$ENVFILE"
cat "$HERE/$ENVFILE"
