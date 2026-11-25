#!/usr/bin/env bash
# Shared helpers, sourced by main.sh.

info() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
error() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; }

# apply_tenant_policy <tenant>...: each atespace may read credential Secrets only from its own tenant-<name> namespace.
apply_tenant_policy() {
  {
    echo "policies:"
    echo "  - {atespace: default, allowedNamespaces: [ax-system, default], secretSelector: {matchLabels: {ax.io/credential: \"true\"}}}"
    for t in "$@"; do
      echo "  - {atespace: $t, allowedNamespaces: [tenant-$t], secretSelector: {matchLabels: {ax.io/credential: \"true\"}}}"
    done
  } > /tmp/tenant-policy.yaml
  kubectl -n ate-system create configmap k8s-credential-provider-namespace-policy \
    --from-file=namespace-policy.yaml=/tmp/tenant-policy.yaml --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n ate-system rollout restart deploy/k8s-credential-provider >/dev/null
  kubectl -n ate-system rollout status deploy/k8s-credential-provider --timeout=120s >/dev/null
}

# render <dir> '<vars>': build a kustomization from resources/ and fill ${VARS} (envsubst) from the environment.
# The root is the repo root, so callers need not care about the working directory.
render() {
  kubectl kustomize "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/$1" | envsubst "$2"
}
