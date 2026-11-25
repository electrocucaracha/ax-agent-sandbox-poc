#!/usr/bin/env bash
# Team demo: an epic reported as an issue on the git server, broken down by a triage agent, worked in parallel by
# role agents and delivered as pull requests.
#   alpha (epic: config-file support for Click, see agents/epic.md; reported as issue #1 on alpha/app)
#     wave 0: triage-lead reads issue #1 and creates one "[role:<name>]" issue per role
#             (if it creates none, as with the canned mock LLM, the script creates them from a fixed plan)
#     wave 1 builders, one per role issue, in parallel: developer, quality, mutation, docs, ux, sre, product-owner
#     wave 2 reviewers, after the PRs exist: principal, security, performance
#     checks: ci-check (shell agent; proves push and PR creation through the gateway)
#   beta: triage (read-only) on beta/app
# Every task starts from a snapshot of a Workspace cloned from the in-cluster git server.
# Credentials (git token, LLM key) are injected by the egress gateway and never enter a sandbox.
#   Also checks: unlisted hosts are refused, /workspace survives suspend and resume, tenants cannot read each other's repos.
# Needs 05-mock-llm.sh, 09-git-server.sh and the image (.env.opencode). `down` cleans up.
# Env: LLM_HOST (default mock-llm.default.svc.cluster.local), LLM_PATH (/v1), OC_CONFIG (/opt/opencode.json),
#      LLM_API_KEY (default: a fake key per tenant), WORKERS (default: tasks running at once), EPIC_TIMEOUT (seconds per wave, 1800)
set -euo pipefail
export PATH="$HOME/.ax/bin:$PATH"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/.env.opencode"
# shellcheck disable=SC1091
source "$HERE/scripts/_utils.sh"
export OPENCODE_IMAGE LLM_HOST=${LLM_HOST:-mock-llm.default.svc.cluster.local} LLM_PATH=${LLM_PATH:-/v1} OC_CONFIG=${OC_CONFIG:-/opt/opencode.json} HOLD_SECONDS=${HOLD_SECONDS:-900}
TENANTS="alpha beta"
ADMIN_PASS=${GIT_ADMIN_PASS:-admin-pass-123}
# wave|tenant|task|spec|issue, where spec is epic:<role> (epic + team rules + agents/<role>.md + the role's issue),
# prompt:<file> (agents/<file>.md as is) or script:<file> (agents/<file>.sh, for agents that need no LLM).
# Waves 1 and 2 are added after triage, one per "[role:<name>]" issue.
ROLES=(
  "0|alpha|ci-check|script:ci-check"
  "0|beta|triage|prompt:triage"
  "0|alpha|triage-lead|prompt:triage-epic"
)
BUILDERS="developer quality mutation docs ux sre product-owner"
REVIEWERS="principal security performance"
EPIC_TIMEOUT=${EPIC_TIMEOUT:-1800}
in_wave() { local r; for r in "${ROLES[@]}"; do IFS='|' read -r w t role _ <<< "$r"; [ "$w" = "$1" ] && echo "$t/$role"; done; return 0; }

if [ "${1:-}" = down ]; then
  for r in "${ROLES[@]}"; do IFS='|' read -r _ t role _ <<< "$r"; ax -a "$t" delete task "$role" 2>/dev/null || true; done
  for role in $BUILDERS $REVIEWERS; do ax -a alpha delete task "$role" 2>/dev/null || true; done
  for t in $TENANTS; do ax -a "$t" delete workspace "$t-app" 2>/dev/null || true; ax -a "$t" delete gateway team-gw 2>/dev/null || true; done
  ax -a beta delete workspace beta-x 2>/dev/null || true
  kubectl -n ate-workers patch workerpool ax-workers --type=merge -p '{"spec":{"replicas":1}}'
  exit 0
fi

info "Scale workers"
kubectl -n ate-workers patch workerpool ax-workers --type=merge -p '{"spec":{"replicas":'"${WORKERS:-$(( $(in_wave 0 | wc -l) + $(echo $BUILDERS | wc -w) ))}"'}}'

info "Per-tenant git user, private repo and tokens; LLM key Secret"
pf_up() { kubectl -n default port-forward svc/git 8443:443 >/dev/null 2>&1 & PF=$!; sleep 3; }
pf_down() { kill "$PF" 2>/dev/null || true; } # a bare `wait` would otherwise block on the port-forward
PF=
trap 'pf_down' EXIT
pf_up
API=https://localhost:8443/api/v1
export GIT_API=$API GIT_USER=alpha GIT_PASS=pass-alpha-123
TMP=$(mktemp -d); cp -R "$HERE/image/sample-repo/." "$TMP/"
git -C "$TMP" init -q -b main && git -C "$TMP" add -A
git -C "$TMP" -c user.name=seed -c user.email=seed@example.com commit -qm "seed from sample repo"
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
rm -rf "$TMP"
pf_down
apply_tenant_policy $TENANTS
kubectl -n ate-workers rollout status deploy/ax-workers --timeout=180s >/dev/null || true

info "Clone each tenant's repo into a Workspace"
for t in $TENANTS; do
  TENANT=$t WS=$t-app REPO=$t/app render resources/team '${TENANT} ${WS} ${REPO} ${LLM_HOST} ${OPENCODE_IMAGE}' | ax apply -f - >/dev/null &
done
wait
for t in $TENANTS; do echo "$t: $(ax -a "$t" describe workspace "$t-app" | grep Phase)"; done

info "Report the epic as issue #1 on alpha/app"
pf_up
EPIC_ISSUE=$(python3 "$HERE/scripts/issues.py" epic alpha/app "$HERE/agents/epic.md")
pf_down
echo "epic issue: #$EPIC_ISSUE"

start_agents() { # wave
  local r w t role spec issue src file
  for r in "${ROLES[@]}"; do
    IFS='|' read -r w t role spec issue <<< "$r"
    [ "$w" = "$1" ] || continue
    ax -a "$t" delete task "$role" >/dev/null 2>&1 || true
    case $spec in
      epic:*)
        common=_builder; [ "$w" = 2 ] && common=_reviewer
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
    # base64 keeps the multi-line prompt out of the YAML quoting; the task decodes it inside the sandbox
    PROMPT_B64=$(base64 < "$file" | tr -d '\n')
    TENANT=$t TASK=$role WS=$t-app RUNNER=$RUNNER PROMPT_B64=$PROMPT_B64 render resources/task '${TENANT} ${TASK} ${WS} ${RUNNER} ${PROMPT_B64} ${LLM_HOST} ${LLM_PATH} ${OC_CONFIG} ${HOLD_SECONDS}' | ax apply -f - >/dev/null
    ax -a "$t" resume task "$role" >/dev/null &
  done
  wait
}

wait_for() { # tenant/task...: wait for /workspace/done in each task
  local deadline=$(( SECONDS + EPIC_TIMEOUT )) pending a
  while :; do
    pending=""
    for a in "$@"; do
      ax -a "${a%/*}" ssh "${a#*/}" -- test -f /workspace/done >/dev/null 2>&1 || pending="$pending $a"
    done
    [ -z "$pending" ] && return 0
    if [ $SECONDS -ge $deadline ]; then echo "timeout; still running:$pending"; return 0; fi
    echo "waiting for:$pending"; sleep 20
  done
}

wait_wave() { wait_for $(in_wave "$1"); }

show_outputs() { # wave
  local a
  for a in $(in_wave "$1"); do echo "-- $a"; ax -a "${a%/*}" ssh "${a#*/}" -- head -8 /workspace/out.log || true; done
}

info "Wave 0: triage-lead breaks the epic into role issues (ci-check and beta triage run alongside)"
start_agents 0
wait_for alpha/triage-lead
ax -a alpha delete task triage-lead >/dev/null 2>&1 || true # free its worker
KEEP=(); for r in "${ROLES[@]}"; do case $r in *"|triage-lead|"*) ;; *) KEEP+=("$r") ;; esac; done; ROLES=("${KEEP[@]}")
ISSUE_DIR=$(mktemp -d)
pf_up
role_issues() { python3 "$HERE/scripts/issues.py" list alpha/app | grep -E "\|($(echo $BUILDERS $REVIEWERS | tr ' ' '|'))\$" || true; }
if [ -z "$(role_issues)" ]; then
  echo "triage-lead created no role issues (expected with the canned mock LLM): creating them from the fixed plan"
  python3 "$HERE/scripts/issues.py" fallback alpha/app
fi
seen=" "
while IFS='|' read -r n role; do
  case $seen in *" $role "*) continue ;; esac; seen="$seen$role "
  python3 "$HERE/scripts/issues.py" body alpha/app "$n" > "$ISSUE_DIR/$n.md"
  case " $REVIEWERS " in *" $role "*) w=2 ;; *) w=1 ;; esac
  ROLES+=("$w|alpha|$role|epic:$role|$n")
  echo "issue #$n -> $role (wave $w)"
done < <(role_issues)
pf_down

info "Wave 1: builders work in parallel, one per issue"
start_agents 1
wait_wave 1; wait_wave 0
info "Tasks per atespace"
for t in $TENANTS; do echo "-- $t"; ax -a "$t" get tasks; done
info "Output of each agent"
show_outputs 0; show_outputs 1
for a in $(in_wave 1); do ax -a "${a%/*}" delete task "${a#*/}" >/dev/null 2>&1 || true; done # free the workers; the PRs stay on the git server

info "Wave 2: reviewers read the pull requests"
start_agents 2
wait_wave 2
show_outputs 2

info "Pull requests on alpha/app"
kubectl -n default port-forward svc/git 8443:443 >/dev/null 2>&1 &
PF=$!
sleep 3
curl -sk -u "alpha:pass-alpha-123" "$API/repos/alpha/app/pulls?state=all" | python3 -c 'import json,sys; [print("#%d %s [%s] comments=%d" % (p["number"], p["title"], p["head"]["ref"], p["comments"])) for p in json.load(sys.stdin)]' || true
curl -sk -u "alpha:pass-alpha-123" "$API/repos/alpha/app/issues?type=issues&state=all&limit=50" | python3 -c 'import json,sys; [print("issue #%d %s comments=%d" % (i["number"], i["title"][:70], i["comments"])) for i in json.load(sys.stdin)]' || true
kill "$PF" 2>/dev/null || true

info "Suspend and resume ci-check: /workspace must survive"
ax -a alpha ssh ci-check -- sh -c "date +%s > /workspace/marker"
ax -a alpha suspend task ci-check >/dev/null && sleep 5
ax -a alpha resume task ci-check >/dev/null && sleep 15
echo "marker after resume: $(ax -a alpha ssh ci-check -- cat /workspace/marker)"
info "Credentials in a sandbox (placeholder only; no git token)"
ax -a alpha ssh ci-check -- sh -c 'env | grep -ci token; env | grep LITELLM' || true
info "Tenant boundary: beta tries to clone alpha's repo with its own token (expect Failed)"
TENANT=beta WS=beta-x REPO=alpha/app render resources/team '${TENANT} ${WS} ${REPO} ${LLM_HOST} ${OPENCODE_IMAGE}' | ax apply -f - 2>&1 | tail -1 | cut -c1-160 || true
ax -a beta describe workspace beta-x | grep Phase || true
