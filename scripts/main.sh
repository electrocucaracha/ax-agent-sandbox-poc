#!/usr/bin/env bash
# Run the numbered scripts as named phases, in the order given.
#   scripts/main.sh                      # default phases
#   scripts/main.sh image agent          # chosen phases
#   IMAGE_SOURCE=external OPENCODE_IMAGE=registry/image@sha256:<digest> scripts/main.sh
#   PHASES="cluster image" scripts/main.sh
#   scripts/main.sh list                 # show phases
# DEBUG=true traces every command. Environment variables pass through to each script.
set -o pipefail
set -o errexit
set -o nounset
[[ ${DEBUG:-false} != "true" ]] || set -o xtrace

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.."
# shellcheck source=./scripts/_utils.sh
source "$HERE/_utils.sh"

declare -A PHASE_CMD=(
    [preflight]="00-preflight.sh"
    [install]="01-install-ax.sh"
    [cluster]="02-start-cluster.sh"
    [image]="03-build-push-image.sh"
    [mock-llm]="05-mock-llm.sh"
    [headroom]="07-headroom.sh"
    [git-server]="09-git-server.sh"
    [team-demo]="10-team-demo.sh"
    [team-demo-down]="10-team-demo.sh down"
    [teardown]="99-teardown.sh"
)
PHASE_ORDER=(preflight install cluster image mock-llm headroom git-server team-demo team-demo-down teardown)
DEFAULT_PHASES="preflight install cluster image mock-llm git-server team-demo"

if [[ ${1:-} == "list" ]]; then
    for p in "${PHASE_ORDER[@]}"; do printf '%-18s %s\n' "$p" "${PHASE_CMD[$p]}"; done
    echo "default: $DEFAULT_PHASES"
    exit 0
fi

phases=("$@")
[[ ${#phases[@]} -gt 0 ]] || read -r -a phases <<<"${PHASES:-$DEFAULT_PHASES}"

# Validate every phase before running any.
for p in "${phases[@]}"; do
    [[ -n ${PHASE_CMD[$p]:-} ]] || { error "unknown phase '$p' (try: $0 list)"; exit 2; }
done

for p in "${phases[@]}"; do
    info "Phase: $p"
    read -r -a cmd <<<"${PHASE_CMD[$p]}"
    bash "$HERE/${cmd[0]}" "${cmd[@]:1}"
done
info "Done: ${phases[*]}"
