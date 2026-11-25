#!/usr/bin/env bash
# Expose an Ollama server running on the host as https://ollama.default.svc.cluster.local (443).
# A small in-cluster TLS proxy forwards to the host, because the egress gateway only speaks HTTPS upstream.
# Needs 05-mock-llm.sh first (CA and egress trust). Env: OLLAMA_MODEL (default qwen2.5-coder:7b),
# OLLAMA_UPSTREAM (default host.containers.internal:11434).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CERTS="$HERE/certs"
# shellcheck source=./scripts/_utils.sh
source "$HERE/scripts/_utils.sh"
HOST=ollama.default.svc.cluster.local
MODEL=${OLLAMA_MODEL:-qwen2.5-coder:7b}
UPSTREAM=${OLLAMA_UPSTREAM:-host.containers.internal:11434}

[ -f "$CERTS/ca.key" ] || { echo "run scripts/main.sh mock-llm first (creates the CA)"; exit 1; }
curl -fsS "http://localhost:${UPSTREAM##*:}/api/tags" >/dev/null || { echo "Ollama is not answering on localhost:${UPSTREAM##*:}"; exit 1; }
ollama list | grep -q "^$MODEL" || ollama pull "$MODEL" || echo "WARN: model $MODEL not available locally; pull it before running the demo"

if [ ! -f "$CERTS/ollama.crt" ]; then
  openssl req -newkey rsa:2048 -nodes -subj "/CN=$HOST" -keyout "$CERTS/ollama.key" -out "$CERTS/ollama.csr"
  printf "subjectAltName=DNS:%s\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n" "$HOST" > "$CERTS/ollama.ext"
  openssl x509 -req -in "$CERTS/ollama.csr" -CA "$CERTS/ca.crt" -CAkey "$CERTS/ca.key" -CAcreateserial \
    -days 30 -extfile "$CERTS/ollama.ext" -out "$CERTS/ollama.crt"
fi

kubectl -n default create secret tls ollama-tls --cert="$CERTS/ollama.crt" --key="$CERTS/ollama.key" --dry-run=client -o yaml | kubectl apply -f -
UPSTREAM=$UPSTREAM render resources/ollama '${UPSTREAM}' | kubectl apply -f -
kubectl -n default rollout status deploy/ollama --timeout=300s
echo "ollama ready: https://$HOST/v1 (model $MODEL)"
