#!/usr/bin/env bash
# Deploy an in-cluster Git server (Gitea; Forgejo is a fork with the same role) at git.default.svc.cluster.local:443,
# signed by the mock CA that the egress gateway already trusts (run 05-mock-llm.sh first).
# Creates an admin user. Per-tenant users, repos and tokens are created by 10-team-demo.sh.
# Env: GIT_IMAGE (default docker.io/gitea/gitea:1.24)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.ax/bin:$PATH"
HOST=git.default.svc.cluster.local
CERTS="$HERE/certs"
# shellcheck source=./scripts/_utils.sh
source "$HERE/scripts/_utils.sh"
IMG=${GIT_IMAGE:-docker.io/gitea/gitea:1.24}

if [ ! -f "$CERTS/git.crt" ]; then
  openssl req -newkey rsa:2048 -nodes -subj "/CN=$HOST" -keyout "$CERTS/git.key" -out "$CERTS/git.csr"
  printf "subjectAltName=DNS:%s\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n" "$HOST" > "$CERTS/git.ext"
  openssl x509 -req -in "$CERTS/git.csr" -CA "$CERTS/ca.crt" -CAkey "$CERTS/ca.key" -CAcreateserial -days 30 -extfile "$CERTS/git.ext" -out "$CERTS/git.crt"
fi

podman image exists "$IMG" || podman pull "$IMG"
podman save "$IMG" -o "$HOME/git-image.tar"
kind load image-archive "$HOME/git-image.tar" --name ax-local && rm -f "$HOME/git-image.tar"

kubectl -n default create secret tls git-tls --cert="$CERTS/git.crt" --key="$CERTS/git.key" --dry-run=client -o yaml | kubectl apply -f -
GIT_IMAGE=$IMG render resources/git-server '${GIT_IMAGE}' | kubectl apply -f -
kubectl -n default rollout status deploy/git --timeout=300s

# Admin user.
ADMIN_PASS=${GIT_ADMIN_PASS:-admin-pass-123}
kubectl -n default exec deploy/git -- su git -s /bin/sh -c "gitea admin user create --admin --username admin --password '$ADMIN_PASS' \
  --email admin@example.com --must-change-password=false" 2>&1 | tail -1 || true

echo "git ready: https://$HOST (admin / $ADMIN_PASS)"
