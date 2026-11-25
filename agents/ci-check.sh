# A resumed task runs this again; show the first result instead of repeating the push.
[ -f /workspace/ci-check.log ] && { cat /workspace/ci-check.log; exit 0; }
{
cd /workspace/repo
python3 -m compileall -q src && echo compile-ok
git log --oneline | head -3
echo blocked-host=$(curl -s -m 8 -o /dev/null -w %{http_code} https://example.com || echo refused)
# Plumbing check: push and PR creation work with gateway-injected credentials and no token in the sandbox.
# The gateway replaces an Authorization header only if the request has one, so API calls send a placeholder.
REPO=$(git remote get-url origin | sed 's#.*/\([^/]*/[^/]*\)\.git#\1#')
git checkout -q -b ci-check/plumbing
echo "plumbing check" > .ci-check
git add .ci-check
git -c user.name=ci-check -c user.email=ci-check@example.com commit -qm "ci-check: plumbing"
git push -q -u origin ci-check/plumbing && echo push=ok || echo push=failed
echo '{"title":"[ci-check] plumbing","head":"ci-check/plumbing","base":"main","body":"Checks push and PR creation."}' > /tmp/pr.json
echo pr-http=$(curl -s -o /dev/null -w %{http_code} -X POST -H 'Authorization: token placeholder' -H 'Content-Type: application/json' --data @/tmp/pr.json "https://git.default.svc.cluster.local/api/v1/repos/$REPO/pulls")
# Triage path: a sandbox can read an issue and comment on it (no new issues, so the role list stays clean).
echo issue-read-http=$(curl -s -o /dev/null -w %{http_code} -H 'Authorization: token placeholder' "https://git.default.svc.cluster.local/api/v1/repos/$REPO/issues/1")
echo '{"body":"ci-check: issue API reachable from the sandbox."}' > /tmp/c.json
echo issue-comment-http=$(curl -s -o /dev/null -w %{http_code} -X POST -H 'Authorization: token placeholder' -H 'Content-Type: application/json' --data @/tmp/c.json "https://git.default.svc.cluster.local/api/v1/repos/$REPO/issues/1/comments")
} 2>&1 | tee /workspace/ci-check.log
