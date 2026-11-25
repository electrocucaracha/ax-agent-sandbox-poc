#!/usr/bin/env bash
# Deploy an in-cluster TLS mock OpenAI/LiteLLM endpoint (mock-llm.default.svc.cluster.local:443) and make the
# Substrate egress gateway trust its CA. The gateway validates upstream certs against the CA bundle in its image,
# so we replace that bundle with: podman VM bundle (includes any corporate CAs) + mock CA. The same trick is needed
# for any internal LiteLLM host signed by a private CA.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HOST=mock-llm.default.svc.cluster.local
CERTS="$HERE/certs"; mkdir -p "$CERTS"

if [ ! -f "$CERTS/tls.crt" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=poc-mock-ca" \
    -keyout "$CERTS/ca.key" -out "$CERTS/ca.crt" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign"
  openssl req -newkey rsa:2048 -nodes -subj "/CN=$HOST" -keyout "$CERTS/tls.key" -out "$CERTS/tls.csr"
  printf "subjectAltName=DNS:%s\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n" "$HOST" > "$CERTS/ext.cnf"
  openssl x509 -req -in "$CERTS/tls.csr" -CA "$CERTS/ca.crt" -CAkey "$CERTS/ca.key" -CAcreateserial \
    -days 30 -extfile "$CERTS/ext.cnf" -out "$CERTS/tls.crt"
fi

kubectl -n default create secret tls mock-llm-tls --cert="$CERTS/tls.crt" --key="$CERTS/tls.key" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k "$HERE/resources/mock-llm"

# Trust bundle for the egress gateway's upstream TLS.
podman machine ssh 'cat /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' > "$CERTS/egress-bundle.pem"
cat "$CERTS/ca.crt" >> "$CERTS/egress-bundle.pem"
kubectl -n ate-system delete configmap egress-upstream-ca --ignore-not-found
kubectl -n ate-system create configmap egress-upstream-ca --from-file=ca-certificates.crt="$CERTS/egress-bundle.pem"

if ! kubectl -n ate-system get deploy atenet-egress -o json | grep -q egress-upstream-ca; then
  kubectl -n ate-system patch deploy atenet-egress --type=json --patch-file "$HERE/resources/egress-trust/patch.json"
fi
kubectl -n ate-system rollout status deploy/atenet-egress --timeout=300s
kubectl -n default rollout status deploy/mock-llm --timeout=300s
echo "mock ready: https://$HOST"
