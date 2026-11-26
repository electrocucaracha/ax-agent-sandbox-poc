#!/usr/bin/env bash
# Team demo: an epic reported as an issue on the git server, broken down by a triage agent, worked in parallel by
# role agents and delivered as pull requests.
#   alpha (epic: config-file support for Click, see agents/epic.md; reported as issue #1 on alpha/app)
#     wave 0: triage-lead reads issue #1 and creates one "[role:<name>]" issue per role
#             (if it creates none, as with the canned mock LLM, the script creates them from a fixed plan)
#     wave 1 builders, one per role issue, in parallel: developer, quality, docs, ux, sre, product-owner
#     wave 2 mutation, after the implementation and test branches exist
#     wave 3 reviewers, after the PRs exist: principal, security, performance
#     checks: ci-check (shell agent; proves push and PR creation through the gateway)
#   beta: triage (read-only) on beta/app
# Every task starts from a snapshot of a Workspace cloned from the in-cluster git server.
# Credentials (git token, LLM key) are injected by the egress gateway and never enter a sandbox.
#   Also checks: unlisted hosts are refused, /workspace survives suspend and resume, tenants cannot read each other's repos.
# Needs 05-mock-llm.sh, 09-git-server.sh and the image (.env.opencode). `down` cleans up.
# Env: OPENCODE_IMAGE, LLM_HOST, LLM_PATH, LLM_MODEL_ID, LLM_AUTH_MODE, LLM_EXTRA_HEADERS_JSON, OC_CONFIG,
#      LLM_API_KEY, LITELLM_PROXY_API_BASE, LITELLM_PROXY_API_KEY, OLLAMA_URL, WORKERS, EPIC_TIMEOUT, MUTATION_MEMORY, MUTATION_TIMEOUT,
#      SAMPLE_REPO_URL and SAMPLE_REPO_REF (used when image/sample-repo is absent),
#      ACCURACY_REPETITIONS (default 1) and USAGE_REPORT_DIR (default .cache/team-demo-usage) for the final usage report
set -euo pipefail
export PATH="$HOME/.ax/bin:$PATH"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE_OVERRIDE=${OPENCODE_IMAGE:-}
# shellcheck disable=SC1091
source "$HERE/scripts/_utils.sh"
if [[ -f "$HERE/.env.opencode" ]]; then
  # shellcheck disable=SC1091
  source "$HERE/.env.opencode"
fi
OPENCODE_IMAGE=${IMAGE_OVERRIDE:-${OPENCODE_IMAGE:-}}
DEFAULT_OC_CONFIG=/opt/opencode.json
# An external Ollama server (see 06-ollama.sh) is an OpenAI-compatible endpoint at /v1 behind the egress gateway.
if [[ -n "${OLLAMA_URL:-}" && -z "${LITELLM_PROXY_API_BASE:-}" ]]; then
  LITELLM_PROXY_API_BASE="${OLLAMA_URL%/}/v1"
  LLM_API_KEY=${LLM_API_KEY:-ollama}
  DEFAULT_OC_CONFIG=/opt/opencode.ollama.json
fi
if [[ -n "${LITELLM_PROXY_API_BASE:-}" ]]; then
  proxy_endpoint=$(python3 - "$LITELLM_PROXY_API_BASE" <<'PY'
import sys
from urllib.parse import urlsplit

try:
    url = urlsplit(sys.argv[1])
    url.port
except ValueError as error:
    raise SystemExit("LITELLM_PROXY_API_BASE must be a valid HTTPS base URL") from error

if (
    url.scheme != "https"
    or not url.netloc
    or url.username is not None
    or url.password is not None
    or url.query
    or url.fragment
    or any(character.isspace() for character in sys.argv[1])
):
    raise SystemExit(
        "LITELLM_PROXY_API_BASE must be an HTTPS base URL without credentials, "
        "query, or fragment"
    )

path = url.path.rstrip("/")
if path.endswith("/v1"):
    path = path[:-3].rstrip("/")
print(f"{url.netloc}{path}\t/v1")
PY
  ) || exit 1
  IFS=$'\t' read -r LLM_HOST LLM_PATH <<< "$proxy_endpoint"
else
  LLM_HOST=${LLM_HOST:-mock-llm.default.svc.cluster.local}
  LLM_PATH=${LLM_PATH:-/v1}
fi
LLM_MODEL_ID=${LLM_MODEL_ID:-}
if [[ -z "$LLM_MODEL_ID" && "${LITELLM_PROXY_MODEL:-}" == anthropic/* ]]; then
  LLM_MODEL_ID=${LITELLM_PROXY_MODEL#anthropic/}
fi
LLM_API_KEY=${LITELLM_PROXY_API_KEY:-${LLM_API_KEY:-}}
LLM_AUTH_MODE=${LLM_AUTH_MODE:-both}
LLM_EXTRA_HEADERS_JSON=${CHANGELOG_LITELLM_HEADERS_JSON:-${LLM_EXTRA_HEADERS_JSON:-${LITELLM_EXTRA_HEADERS_JSON:-}}}
EXTRA_HEADERS_B64=$(printf %s "$LLM_EXTRA_HEADERS_JSON" | base64 | tr -d '\n')
case "$LLM_AUTH_MODE" in
  both|x-api-key) ;;
  *) error "LLM_AUTH_MODE must be 'both' or 'x-api-key'"; exit 1 ;;
esac
TEAM_RESOURCES=resources/team
[[ "$LLM_AUTH_MODE" == both ]] && TEAM_RESOURCES=resources/team-both
if [[ "$LLM_HOST" == */* ]]; then
  LLM_BASE_PATH=${LLM_HOST#*/}
  LLM_HOST=${LLM_HOST%%/*}
  if [[ -n "$LLM_BASE_PATH" ]]; then
    LLM_PATH="/${LLM_BASE_PATH%/}/${LLM_PATH#/}"
    LLM_PATH=${LLM_PATH%/}
    [[ -n "$LLM_PATH" ]] || LLM_PATH=/
  fi
fi
export OPENCODE_IMAGE LLM_HOST LLM_PATH LLM_MODEL_ID LLM_AUTH_MODE OC_CONFIG=${OC_CONFIG:-$DEFAULT_OC_CONFIG}
[[ -n ${OPENCODE_IMAGE:-} ]] || { error "OPENCODE_IMAGE missing; build the agent image first"; exit 1; }
SAMPLE_REPO_URL=${SAMPLE_REPO_URL:-https://github.com/pallets/click.git}
SAMPLE_REPO_REF=${SAMPLE_REPO_REF:-8.1.8}
TENANTS="alpha beta"
ADMIN_PASS=${GIT_ADMIN_PASS:-admin-pass-123}
# wave|tenant|task|spec|issue, where spec is epic:<role> (epic + team rules + agents/<role>.md + the role's issue),
# prompt:<file> (agents/<file>.md as is) or script:<file> (agents/<file>.sh, for agents that need no LLM).
# Waves 1 through 3 are added after triage, one per "[role:<name>]" issue.
ROLES=(
  "0|alpha|ci-check|script:ci-check"
  "0|beta|triage|prompt:triage"
  "0|alpha|triage-lead|prompt:triage-epic"
)
BUILDERS="developer quality mutation docs ux sre product-owner"
REVIEWERS="principal security performance"
EPIC_TIMEOUT=${EPIC_TIMEOUT:-1800}
MUTATION_MEMORY=${MUTATION_MEMORY:-2Gi}
MUTATION_TIMEOUT=${MUTATION_TIMEOUT:-3600}
export HOLD_SECONDS=${HOLD_SECONDS:-$((3 * EPIC_TIMEOUT + MUTATION_TIMEOUT + 300))}
in_wave() { local r; for r in "${ROLES[@]}"; do IFS='|' read -r w t role _ <<< "$r"; [ "$w" = "$1" ] && echo "$t/$role"; done; return 0; }

if [ "${1:-}" = down ]; then
  for r in "${ROLES[@]}"; do IFS='|' read -r _ t role _ <<< "$r"; ax -a "$t" delete task "$role" 2>/dev/null || true; done
  for role in $BUILDERS $REVIEWERS; do ax -a alpha delete task "$role" 2>/dev/null || true; done
  for t in $TENANTS; do ax -a "$t" delete workspace "$t-app" 2>/dev/null || true; ax -a "$t" delete gateway team-gw 2>/dev/null || true; done
  ax -a beta delete workspace beta-x 2>/dev/null || true
  kubectl -n ate-workers patch workerpool ax-workers --type=merge -p '{"spec":{"replicas":1}}'
  exit 0
fi

PF=
TMP=
pf_up() { kubectl -n default port-forward svc/git 8443:443 >/dev/null 2>&1 & PF=$!; sleep 3; }
pf_down() { [[ -z "$PF" ]] || kill "$PF" 2>/dev/null || true; PF=; }
cleanup() {
  pf_down
  if [[ -n "$TMP" ]]; then rm -rf "$TMP"; fi
}
trap cleanup EXIT

TMP=$(mktemp -d)
if [[ -d "$HERE/image/sample-repo" ]]; then
  cp -R "$HERE/image/sample-repo/." "$TMP/"
else
  info "Fetch pinned seed repository at ref $SAMPLE_REPO_REF"
  git clone --quiet --depth 1 --branch "$SAMPLE_REPO_REF" "$SAMPLE_REPO_URL" "$TMP"
fi
rm -rf "$TMP/.git"
git -C "$TMP" init -q -b main
git -C "$TMP" add -A
git -C "$TMP" -c user.name=seed -c user.email=seed@example.com commit -qm "seed from sample repo"

info "Scale workers"
kubectl -n ate-workers patch workerpool ax-workers --type=merge -p '{"spec":{"replicas":'"${WORKERS:-$(( $(in_wave 0 | wc -l) + $(echo $BUILDERS | wc -w) ))}"'}}'

info "Per-tenant git user, private repo and tokens; LLM key Secret"
pf_up
API=https://localhost:8443/api/v1
export GIT_API=$API GIT_USER=alpha GIT_PASS=pass-alpha-123
gitea() { kubectl -n default exec deploy/git -- su git -s /bin/sh -c "gitea admin user $1"; }
for t in $TENANTS; do
  kubectl create ns "tenant-$t" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  gitea "create --username $t --password pass-$t-123 --email $t@example.com --must-change-password=false" >/dev/null 2>&1 || true
  curl -sk -u "$t:pass-$t-123" -X DELETE "$API/repos/$t/app" -o /dev/null || true # start from a clean repo: no old branches or PRs
  curl -sk -u "$t:pass-$t-123" -X POST "$API/user/repos" -H 'Content-Type: application/json' -d '{"name":"app","private":true}' -o /dev/null || true
  git -C "$TMP" -c http.sslVerify=false push -q --force "https://$t:pass-$t-123@localhost:8443/$t/app.git" main
  tok=$(gitea "generate-access-token --username $t --token-name ax-$(date +%s)-$t --scopes write:repository,write:issue --raw" 2>/dev/null | tail -1)
  kubectl -n "tenant-$t" create secret generic git-token --from-literal=token="$tok" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "tenant-$t" label secret git-token ax.io/credential=true --overwrite >/dev/null
  kubectl -n "tenant-$t" create secret generic llm-key --from-literal=api-key="${LLM_API_KEY:-sk-tenant-$t-KEY}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "tenant-$t" label secret llm-key ax.io/credential=true --overwrite >/dev/null
done
rm -rf "$TMP"; TMP=
pf_down
apply_tenant_policy $TENANTS
kubectl -n ate-workers rollout status deploy/ax-workers --timeout=180s >/dev/null || true

info "Clone each tenant's repo into a Workspace"
for t in $TENANTS; do
  TENANT=$t WS=$t-app REPO=$t/app render "$TEAM_RESOURCES" '${TENANT} ${WS} ${REPO} ${LLM_HOST} ${OPENCODE_IMAGE}' | ax apply -f - >/dev/null &
done
wait
for t in $TENANTS; do echo "$t: $(ax -a "$t" describe workspace "$t-app" | grep Phase)"; done

info "Report the epic as issue #1 on alpha/app"
pf_up
EPIC_ISSUE=$(uv run --quiet --script "$HERE/scripts/issues.py" epic alpha/app "$HERE/agents/epic.md")
pf_down
echo "epic issue: #$EPIC_ISSUE"

start_agents() { # wave
  local r w t role spec issue src file TASK_PROFILE
  for r in "${ROLES[@]}"; do
    IFS='|' read -r w t role spec issue <<< "$r"
    [ "$w" = "$1" ] || continue
    ax -a "$t" delete task "$role" >/dev/null 2>&1 || true
    case $spec in
      epic:*)
        common=_builder; [ "$w" = 3 ] && common=_reviewer
        file=$(mktemp); cat "$HERE/agents/epic.md" "$HERE/agents/$common.md" "$HERE/agents/${spec#epic:}.md" > "$file"
        if [ -n "$issue" ]; then
          { printf '\n## Your assignment\n\nThis is issue #%s on the git server. Put `Closes #%s` in your PR body.\n\n' "$issue" "$issue"; cat "$ISSUE_DIR/$issue.md"; } >> "$file"
        fi
        RUNNER=prompt ;;
      prompt:*)
        file="$HERE/agents/${spec#prompt:}.md"
        RUNNER=prompt ;;
      script:*)
        file="$HERE/agents/${spec#script:}.sh"
        RUNNER=script ;;
    esac
    if [ "$RUNNER" = prompt ]; then
      src=$file
      file=$(mktemp)
      cat "$src" "$HERE/skills/evidence/SKILL.md" > "$file"
      if [ "$role" = mutation ]; then
        cat "$HERE/tools/mutmut.md" >> "$file"
      fi
      [[ "$src" == "$HERE/agents/"* ]] || rm -f "$src"
    fi
    # base64 keeps the multi-line prompt out of the YAML quoting; the task decodes it inside the sandbox
    PROMPT_B64=$(base64 < "$file" | tr -d '\n')
    TASK_PROFILE='{}'
    if [ "$role" = mutation ]; then
      TASK_PROFILE=$(python3 -c 'import json,sys; print(json.dumps({"image": sys.argv[1], "resources": {"limits": {"memory": sys.argv[2]}}}))' "$OPENCODE_IMAGE" "$MUTATION_MEMORY")
    fi
    TENANT=$t TASK=$role WS=$t-app RUNNER=$RUNNER PROMPT_B64=$PROMPT_B64 TASK_PROFILE=$TASK_PROFILE EXTRA_HEADERS_B64=$EXTRA_HEADERS_B64 AUTH_MODE=$LLM_AUTH_MODE render resources/task '${TENANT} ${TASK} ${WS} ${RUNNER} ${PROMPT_B64} ${TASK_PROFILE} ${LLM_HOST} ${LLM_PATH} ${LLM_MODEL_ID} ${EXTRA_HEADERS_B64} ${AUTH_MODE} ${OC_CONFIG} ${HOLD_SECONDS}' | ax apply -f - >/dev/null
    [ "$RUNNER" = script ] || rm -f "$file"
    ax -a "$t" resume task "$role" >/dev/null &
  done
  wait
}

wait_for() { # tenant/task...: wait for /workspace/done in each task
  local deadline=$(( SECONDS + EPIC_TIMEOUT )) pending a
  while :; do
    pending=""
    for a in "$@"; do
      if ax -a "${a%/*}" ssh "${a#*/}" -- test -f /workspace/done >/dev/null 2>&1; then
        continue
      fi
      if ax -a "${a%/*}" ssh "${a#*/}" -- test -f /workspace/failed >/dev/null 2>&1; then
        echo "task failed: $a"
        return 1
      fi
      state=$(ax -a "${a%/*}" get tasks 2>/dev/null | awk -v task="${a#*/}" '$1 == task { print $3; exit }')
      case "$state" in
        Completed) continue ;;
        Failed) echo "task failed: $a"; return 1 ;;
      esac
      pending="$pending $a"
    done
    [ -z "$pending" ] && return 0
    if [ $SECONDS -ge $deadline ]; then echo "timeout; still running:$pending"; return 1; fi
    echo "waiting for:$pending"; sleep 20
  done
}

wait_wave() { wait_for $(in_wave "$1"); }

show_outputs() { # wave
  local a
  for a in $(in_wave "$1"); do echo "-- $a"; ax -a "${a%/*}" ssh "${a#*/}" -- head -8 /workspace/out.log || true; done
}

show_token_stats() { # tenant/task...
  local a
  for a in "$@"; do
    echo "-- token usage: $a"
    ax -a "${a%/*}" ssh "${a#*/}" -- su node -s /bin/sh -c 'HOME=/workspace/home opencode stats' |
      grep -E 'Input|Output|Cache Read|Cache Write'
  done
}

info "Wave 0: triage-lead breaks the epic into role issues (ci-check and beta triage run alongside)"
start_agents 0
wait_for alpha/triage-lead
show_token_stats alpha/triage-lead
ax -a alpha delete task triage-lead >/dev/null 2>&1 || true # free its worker
KEEP=(); for r in "${ROLES[@]}"; do case $r in *"|triage-lead|"*) ;; *) KEEP+=("$r") ;; esac; done; ROLES=("${KEEP[@]}")
ISSUE_DIR=$(mktemp -d)
pf_up
role_issues() { uv run --quiet --script "$HERE/scripts/issues.py" list alpha/app | grep -E "\|($(echo $BUILDERS $REVIEWERS | tr ' ' '|'))\$" || true; }
if [ -z "$(role_issues)" ]; then
  echo "triage-lead created no role issues (expected with the canned mock LLM): creating them from the fixed plan"
  uv run --quiet --script "$HERE/scripts/issues.py" fallback alpha/app
fi
seen=" "
while IFS='|' read -r n role; do
  case $seen in *" $role "*) continue ;; esac; seen="$seen$role "
  uv run --quiet --script "$HERE/scripts/issues.py" body alpha/app "$n" > "$ISSUE_DIR/$n.md"
  if [ "$role" = mutation ]; then
    w=2
  else
    case " $REVIEWERS " in *" $role "*) w=3 ;; *) w=1 ;; esac
  fi
  ROLES+=("$w|alpha|$role|epic:$role|$n")
  echo "issue #$n -> $role (wave $w)"
done < <(role_issues)
pf_down

info "Wave 1: builders work in parallel, one per issue"
start_agents 1
wait_wave 1; wait_wave 0
show_token_stats beta/triage $(in_wave 1)
info "Tasks per atespace"
for t in $TENANTS; do echo "-- $t"; ax -a "$t" get tasks; done
info "Output of each agent"
show_outputs 0; show_outputs 1
for a in $(in_wave 1); do ax -a "${a%/*}" delete task "${a#*/}" >/dev/null 2>&1 || true; done # free the workers; the PRs stay on the git server

info "Wave 2: mutation checks the implementation and test branches"
start_agents 2
EPIC_TIMEOUT=$MUTATION_TIMEOUT wait_wave 2
show_outputs 2
show_token_stats $(in_wave 2)
for a in $(in_wave 2); do ax -a "${a%/*}" delete task "${a#*/}" >/dev/null 2>&1 || true; done

info "Wave 3: reviewers read the pull requests"
start_agents 3
wait_wave 3
show_outputs 3
show_token_stats $(in_wave 3)

info "Pull requests on alpha/app"
kubectl -n default port-forward svc/git 8443:443 >/dev/null 2>&1 &
PF=$!
sleep 3
curl -sk -u "alpha:pass-alpha-123" "$API/repos/alpha/app/pulls?state=all" | python3 -c 'import json,sys; [print("#%d %s [%s] comments=%d" % (p["number"], p["title"], p["head"]["ref"], p["comments"])) for p in json.load(sys.stdin)]' || true
curl -sk -u "alpha:pass-alpha-123" "$API/repos/alpha/app/issues?type=issues&state=all&limit=50" | python3 -c 'import json,sys; [print("issue #%d %s comments=%d" % (i["number"], i["title"][:70], i["comments"])) for i in json.load(sys.stdin)]' || true
kill "$PF" 2>/dev/null || true

info "Suspend and resume ci-check: /workspace must survive"
marker=$(date +%s)
ax -a alpha ssh ci-check -- sh -c "printf '%s\n' '$marker' > /workspace/marker"
ax -a alpha suspend task ci-check >/dev/null && sleep 5
ax -a alpha resume task ci-check >/dev/null && sleep 15
restored_marker=$(ax -a alpha ssh ci-check -- cat /workspace/marker)
[[ "$restored_marker" == "$marker" ]] || { error "workspace marker changed across suspend/resume"; exit 1; }
echo "marker after resume: $restored_marker"
info "Credentials in a sandbox (placeholder only; no git token)"
ax -a alpha ssh ci-check -- sh -c 'env | grep -ci token; env | grep LITELLM' || true
info "Tenant boundary: beta tries to clone alpha's repo with its own token (expect Failed)"
TENANT=beta WS=beta-x REPO=alpha/app render "$TEAM_RESOURCES" '${TENANT} ${WS} ${REPO} ${LLM_HOST} ${OPENCODE_IMAGE}' | ax apply -f - 2>&1 | tail -1 | cut -c1-160 || true
phase=$(ax -a beta describe workspace beta-x | awk '/^Phase:/ { print $2 }')
echo "cross-tenant workspace phase: $phase"
[[ "$phase" == Failed ]] || { error "expected beta's cross-tenant clone to fail"; exit 1; }

info "Usage and accuracy: local cost tools, and paired raw vs rtk answers on fixed questions"
USAGE_DIR=${USAGE_REPORT_DIR:-$HERE/.cache/team-demo-usage}
mkdir -p "$USAGE_DIR"
uv run --quiet --script "$HERE/scripts/13-accuracy-eval.py" --repetitions "${ACCURACY_REPETITIONS:-1}" --output "$USAGE_DIR/accuracy-eval.json"
if command -v codeburn >/dev/null; then
  codeburn status > "$USAGE_DIR/codeburn-status.txt" 2>&1 || echo "codeburn status failed" >&2
  codeburn models > "$USAGE_DIR/codeburn-models.txt" 2>&1 || echo "codeburn models failed" >&2
fi
if command -v ccusage >/dev/null; then
  ccusage daily --json --offline > "$USAGE_DIR/ccusage-daily.json" 2>&1 || echo "ccusage daily failed" >&2
fi
echo "usage and accuracy reports: $USAGE_DIR"
