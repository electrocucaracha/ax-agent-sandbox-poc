#!/usr/bin/env bash
# Stand up kind + Agent Substrate + AX via `ax local start`, then smoke-test with the stock example.
# The first start pulls ~570 MB of images and can be slow (serialised pulls, readiness deadlines).
set -euo pipefail
export PATH="$HOME/.ax/bin:$PATH"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# Digests from the v0.4.0-rc.1 release notes (official images aren't defaulted yet).
export AX_SERVER_IMAGE=${AX_SERVER_IMAGE:-ghcr.io/google/ax/ax-server@sha256:95737151ccc54fdb8d99a8a8674f11777d7b08b7108a7b80820a1c502bb71223}
export AX_RUNNER_VOLUME_IMAGE=${AX_RUNNER_VOLUME_IMAGE:-ghcr.io/google/ax/ax-runner-volume@sha256:ac849f8357ac5b412d2d35d9076ef94b00557399d95c52c62353954e2101be07}

ax local start "$@"
ax local status

# Corporate networks may block gs://gvisor (atelet fetch); 02b uploads it to rustfs instead.
"$HERE/scripts/02b-fix-gvisor-asset.sh"

