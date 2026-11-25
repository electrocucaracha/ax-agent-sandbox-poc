#!/usr/bin/env bash
# Deploy Headroom (context-compression proxy) in the cluster as https://headroom.default.svc.cluster.local.
# The agent talks to it through a Gateway rule (credential injected there); Headroom forwards to UPSTREAM_URL.
# Env: UPSTREAM_URL (required, e.g. https://llm.example.com/gateway), HEADROOM_ARGS (extra `headroom proxy` flags)
# Requires 05-mock-llm.sh to have run first (CA and egress trust ConfigMap).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
: "${UPSTREAM_URL:?set UPSTREAM_URL}"
HOST=headroom.default.svc.cluster.local
CERTS="$HERE/certs"
# shellcheck source=./scripts/_utils.sh
source "$HERE/scripts/_utils.sh"
IMG=localhost/headroom:dev # must match resources/headroom/deployment.yaml

podman build -t "$IMG" -f "$HERE/resources/headroom/Dockerfile" "$HERE/resources/headroom"
podman save "$IMG" -o /tmp/headroom.tar
kind load image-archive /tmp/headroom.tar --name ax-local && rm -f /tmp/headroom.tar

printf "subjectAltName=DNS:%s\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n" "$HOST" > "$CERTS/hr-ext.cnf"
openssl req -newkey rsa:2048 -nodes -subj "/CN=$HOST" -keyout "$CERTS/hr.key" -out "$CERTS/hr.csr" 2>/dev/null
openssl x509 -req -in "$CERTS/hr.csr" -CA "$CERTS/ca.crt" -CAkey "$CERTS/ca.key" -CAcreateserial -days 30 \
  -extfile "$CERTS/hr-ext.cnf" -out "$CERTS/hr.crt" 2>/dev/null
kubectl -n default create secret tls headroom-tls --cert="$CERTS/hr.crt" --key="$CERTS/hr.key" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n default delete configmap upstream-ca --ignore-not-found
kubectl -n default create configmap upstream-ca --from-file=ca-certificates.crt="$CERTS/egress-bundle.pem"

render resources/headroom '${UPSTREAM_URL}' | kubectl apply -f -
kubectl -n default rollout restart deploy/headroom
kubectl -n default rollout status deploy/headroom --timeout=300s
echo "headroom ready: https://$HOST"
