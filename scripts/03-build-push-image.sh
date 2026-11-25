#!/usr/bin/env bash
# Build the agent task image (OpenCode, rtk, Engram, Graphify) and push it to a throwaway registry on the kind network.
# Set IMAGE_SOURCE=external to use OPENCODE_IMAGE; local builds remain the default.
# `ax local` creates no registry, and the atelet pulls task images itself, so we run registry:2
# attached to the "kind" network and reference it by private IP (go-containerregistry uses plain
# HTTP for RFC1918 addresses). AX needs images pinned by digest; it's written to the env file.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CTX="$HERE/image"
BASE=${BASE_IMAGE:-docker.io/library/node:22-slim}
REG_NAME=ax-registry
NAME=${IMAGE_NAME:-opencode-task}
ENVVAR=${ENV_VAR:-OPENCODE_IMAGE}
ENVFILE=${ENV_FILE:-.env.opencode}
ENV_PATH="$HERE/$ENVFILE"
IMAGE_OVERRIDE=${OPENCODE_IMAGE:-}
IMAGE_SOURCE_OVERRIDE=${IMAGE_SOURCE:-}

if [[ -f "$ENV_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_PATH"
fi
OPENCODE_IMAGE=${IMAGE_OVERRIDE:-${OPENCODE_IMAGE:-}}
if [[ -n "$IMAGE_SOURCE_OVERRIDE" ]]; then
  IMAGE_SOURCE=$IMAGE_SOURCE_OVERRIDE
elif [[ -n "$IMAGE_OVERRIDE" ]]; then
  IMAGE_SOURCE=external
elif [[ -n ${IMAGE_SOURCE:-} ]]; then
  :
elif [[ -n ${OPENCODE_IMAGE:-} ]]; then
  IMAGE_SOURCE=external
else
  IMAGE_SOURCE=local
fi

write_image_config() {
  local ref=$1 source=$2 tmp
  [[ "$ENVVAR" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "invalid ENV_VAR: $ENVVAR" >&2; exit 1; }
  tmp=$(mktemp)
  if [[ -f "$ENV_PATH" ]]; then
    awk -v image_key="$ENVVAR" \
      '$0 !~ ("^(export[[:space:]]+)?" image_key "=") && $0 !~ "^(export[[:space:]]+)?IMAGE_SOURCE="' \
      "$ENV_PATH" > "$tmp"
  fi
  printf '%s=%s\n' "$ENVVAR" "$ref" >> "$tmp"
  printf 'IMAGE_SOURCE=%s\n' "$source" >> "$tmp"
  mv "$tmp" "$ENV_PATH"
}

case "$IMAGE_SOURCE" in
  external)
    [[ -n ${OPENCODE_IMAGE:-} ]] || { echo "OPENCODE_IMAGE is required for IMAGE_SOURCE=external" >&2; exit 1; }
    [[ "$OPENCODE_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._:/@+-]*$ ]] || {
      echo "invalid OPENCODE_IMAGE reference" >&2
      exit 1
    }
    write_image_config "$OPENCODE_IMAGE" external
    echo "using configured task image; local image build skipped"
    exit 0
    ;;
  local) ;;
  *) echo "IMAGE_SOURCE must be 'local' or 'external'" >&2; exit 1 ;;
esac

for tool in rtk engram; do
  [[ -x "$CTX/$tool" ]] || { echo "missing executable $CTX/$tool; provide local image inputs or select IMAGE_SOURCE=external" >&2; exit 1; }
done
for dir in sample-repo graph; do
  [[ -d "$CTX/$dir" ]] || { echo "missing $CTX/$dir; provide local image inputs or select IMAGE_SOURCE=external" >&2; exit 1; }
done
[[ -f "$CTX/graph/graphify-out/graph.json" ]] || {
  echo "missing $CTX/graph/graphify-out/graph.json; build the Graphify graph or select IMAGE_SOURCE=external" >&2
  exit 1
}

if ! podman ps --format '{{.Names}}' | grep -qx "$REG_NAME"; then
  podman rm -f "$REG_NAME" >/dev/null 2>&1 || true
  podman run -d --name "$REG_NAME" --network kind --restart=always docker.io/library/registry:2 >/dev/null
fi
REG_IP=$(podman inspect "$REG_NAME" --format '{{(index .NetworkSettings.Networks "kind").IPAddress}}')
REG="$REG_IP:5000"
IMG="$REG/$NAME:dev"
echo "registry: $REG"

podman build --build-arg BASE_IMAGE="$BASE" \
  -f "$CTX/Dockerfile" -t "$IMG" "$CTX"
# The push runs inside the podman VM, whose proxy env must exclude the registry IP.
podman machine ssh "sudo env NO_PROXY=$REG_IP no_proxy=$REG_IP podman push --tls-verify=false --digestfile /tmp/$NAME.digest $IMG"

DIGEST=$(podman machine ssh "cat /tmp/$NAME.digest" | tail -1)
[ -n "$DIGEST" ] || { echo "could not resolve digest for $IMG"; exit 1; }
write_image_config "$REG/$NAME@$DIGEST" local
echo "$ENVVAR=$REG/$NAME@$DIGEST"
