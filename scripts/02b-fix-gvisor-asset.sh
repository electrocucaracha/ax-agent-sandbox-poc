#!/usr/bin/env bash
# Workaround for networks where the atelet cannot reach gs://gvisor (e.g. 403 "VPC Service Controls"
# through a corporate proxy). Downloads the gVisor asset on the host (verifying sha256), uploads it
# to the in-cluster rustfs bucket, and adds a SandboxConfig version whose arm64/amd64 gvisor asset
# is an s3:// URL served by Substrate's object-store plugin.
set -euo pipefail
export PATH="$HOME/.ax/bin:$PATH"
CFG=gvisor-default
BUCKET=ate-snapshots            # assets must not live under <snapshot-location>/atespaces/
PREFIX=assets
NEWVER=v8-s3

kubectl get sandboxconfig "$CFG" -o json > /tmp/sandboxconfig.json
DEFAULT=$(jq -r .spec.defaultVersion /tmp/sandboxconfig.json)
[ "$DEFAULT" = "$NEWVER" ] && { echo "already on $NEWVER"; exit 0; }

kubectl -n ate-system port-forward svc/rustfs 19000:9000 >/tmp/rustfs-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null || true' EXIT
for _ in $(seq 20); do curl -s -o /dev/null http://127.0.0.1:19000/ && break; sleep 1; done

# Build the new version from the current default, swapping each arch's url for an s3:// one.
jq --arg d "$DEFAULT" '.spec.versions[] | select(.name==$d)' /tmp/sandboxconfig.json > /tmp/ver.json
for arch in amd64 arm64; do
  URL=$(jq -r ".assets.$arch.gvisor.url" /tmp/ver.json)
  SHA=$(jq -r ".assets.$arch.gvisor.sha256" /tmp/ver.json)
  HTTP=${URL/gs:\/\//https://storage.googleapis.com/}
  KEY="$PREFIX/gvisor-$arch-${SHA:0:12}.tar.zstd"
  F=/tmp/gvisor-$arch.tar.zstd
  echo "== $arch: $HTTP"
  curl -fsSL "$HTTP" -o "$F"
  [ "$(shasum -a 256 "$F" | cut -d' ' -f1)" = "$SHA" ] || { echo "sha256 mismatch for $arch"; exit 1; }
  curl -fsS --aws-sigv4 "aws:amz:us-east-1:s3" --user rustfsadmin:rustfsadmin \
    -T "$F" "http://127.0.0.1:19000/$BUCKET/$KEY"
  jq --arg a "$arch" --arg u "s3://$BUCKET/$KEY" '.assets[$a].gvisor.url=$u' /tmp/ver.json > /tmp/ver2.json && mv /tmp/ver2.json /tmp/ver.json
done
jq --arg n "$NEWVER" '.name=$n | .state="Enabled"' /tmp/ver.json > /tmp/ver2.json && mv /tmp/ver2.json /tmp/ver.json

kubectl patch sandboxconfig "$CFG" --type=json -p "[
  {\"op\":\"add\",\"path\":\"/spec/versions/-\",\"value\":$(cat /tmp/ver.json)},
  {\"op\":\"replace\",\"path\":\"/spec/defaultVersion\",\"value\":\"$NEWVER\"}]"
echo "patched $CFG -> $NEWVER; check: kubectl -n ate-workers describe pod | grep -i SandboxRuntime"
