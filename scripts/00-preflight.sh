#!/usr/bin/env bash
# Preflight: verify (and optionally fix) the container engine for AX + Agent Substrate on kind.
# Needs a rootful engine, Linux kernel >= 6.8 and >= 6 GiB RAM in the VM.
# Usage: 00-preflight.sh [--fix]   (--fix resizes the podman machine to 8 GiB / 4 CPUs)
set -euo pipefail

MIN_MEM_MIB=6144
WANT_MEM_MIB=8192
FIX=${1:-}

ok()   { printf '  [ok]   %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; FAILED=1; }
FAILED=0

echo "== tools"
for c in docker kind kubectl curl; do
  command -v "$c" >/dev/null && ok "$c" || bad "$c missing"
done

echo "== engine"
if docker info 2>&1 | grep -qi buildahVersion; then
  ENGINE=podman
  MACHINE=$(podman machine list --format '{{.Name}}' | head -1 | tr -d '*')
  MEM=$(podman machine inspect "$MACHINE" --format '{{.Resources.Memory}}')
  ROOTFUL=$(podman machine inspect "$MACHINE" --format '{{.Rootful}}')
  KERNEL=$(podman machine ssh "$MACHINE" uname -r | tail -1)
  ok "engine=podman machine=$MACHINE"
  if [ "$MEM" -lt "$MIN_MEM_MIB" ] || [ "$ROOTFUL" != "true" ]; then
    if [ "$FIX" = "--fix" ]; then
      echo "  -> resizing machine (mem=$WANT_MEM_MIB, rootful)"
      podman machine stop "$MACHINE" || true
      podman machine set --memory "$WANT_MEM_MIB" --cpus 4 --rootful "$MACHINE"
      podman machine start "$MACHINE"
      MEM=$WANT_MEM_MIB; ROOTFUL=true
      KERNEL=$(podman machine ssh "$MACHINE" uname -r | tail -1)
    fi
  fi
  [ "$MEM" -ge "$MIN_MEM_MIB" ] && ok "memory ${MEM}MiB" || bad "memory ${MEM}MiB < ${MIN_MEM_MIB} (run with --fix)"
  [ "$ROOTFUL" = "true" ] && ok "rootful" || bad "machine is rootless (run with --fix)"
else
  ENGINE=docker
  MEM=$(( $(docker info --format '{{.MemTotal}}') / 1024 / 1024 ))
  KERNEL=$(docker run --rm alpine uname -r)
  [ "$MEM" -ge "$MIN_MEM_MIB" ] && ok "memory ${MEM}MiB" || bad "memory ${MEM}MiB < ${MIN_MEM_MIB}"
fi

MAJOR=${KERNEL%%.*}; REST=${KERNEL#*.}; MINOR=${REST%%.*}
if [ "$MAJOR" -gt 6 ] || { [ "$MAJOR" -eq 6 ] && [ "$MINOR" -ge 8 ]; }; then
  ok "kernel $KERNEL"
else
  bad "kernel $KERNEL < 6.8"
fi

echo "== corporate proxy / CA (informational)"
echo "  HTTPS_PROXY=${HTTPS_PROXY:-<unset>}  NODE_EXTRA_CA_CERTS=${NODE_EXTRA_CA_CERTS:-<unset>}"

[ "$FAILED" -eq 0 ] && echo "PREFLIGHT OK" || { echo "PREFLIGHT FAILED"; exit 1; }
