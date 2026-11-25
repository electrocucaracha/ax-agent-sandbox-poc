# Host repositories on an in-cluster git server

Run a git server inside the cluster and give each tenant's agents a private clone of their own repository,
without putting a token in the sandbox.

This removes the need to bake sample code into the agent image.

## Prerequisites

- The cluster, mock CA and egress proxy from the quickstart are running.
- The agent image is built and `.env.opencode` exists.
- For per-tenant repositories, run [the team demo](run-team-demo.md), which creates them.

## Deploy the git server

```bash
./scripts/09-git-server.sh
```

The script deploys Gitea at `https://git.default.svc.cluster.local`.
The certificate is signed by the mock CA, so the egress proxy trusts it.
It creates the admin user.
`10-team-demo.sh` then creates each tenant's user, private repository and token Secret.

> Gitea stands in for Forgejo.
> The network proxy used for testing blocks the Forgejo image registries.
> Forgejo is a fork with the same role, but it was not tested here.

## Clone a private repository into a workspace

[resources/team](../../resources/team) is a kustomization with two files, in this order:

1. A Gateway whose `replaceHeaders` rule sets `Authorization: token <secret>` for the git host (plus one for the LLM host).
2. A Workspace with `setup.git` (the repository URL and ref) and `setup.gateway` (that Gateway).

A task mounts the workspace and is bound to the same Gateway (`resources/task/`).

Render it with kustomize, fill the placeholders and apply it:

```bash
set -a; source .env.opencode; set +a
export TENANT=alpha WS=alpha-app REPO=alpha/app LLM_HOST=mock-llm.default.svc.cluster.local
kubectl kustomize resources/team \
  | envsubst '${TENANT} ${WS} ${REPO} ${LLM_HOST} ${OPENCODE_IMAGE}' | ax apply -f -
ax -a alpha describe workspace alpha-app
```

The workspace reaches phase `Ready` with `SetupComplete` and `SnapshotReady`.
The task starts from the snapshot, so the clone is not repeated.

## Verified behaviour

| Check                                                 | Result                                           |
| ----------------------------------------------------- | ------------------------------------------------ |
| Private clone with an injecting Gateway               | Works                                            |
| Token visible in sandbox environment or git config    | No (0 matches)                                   |
| Two tenants clone their own private repo concurrently | Both workspaces `Ready`                          |
| Tenant `beta` clones `alpha/app` using its own token  | Workspace `Failed`, `git fetch: exit status 128` |

## Things to know

- `setup.git` accepts HTTPS URLs only and has no credential field.
  Credentials come only from the Gateway.
- `setup.gateway` applies to the setup actor.
  Tasks do not inherit it, so bind a Gateway to the task as well.
- Egress replaces an `Authorization` header only when the request already has one, as the upstream documentation says.
  `git` authenticates without help, but API calls need a placeholder: `curl -H 'Authorization: token placeholder' ...`.
  Without it, a private repository returns 404.
- The team demo uses a token with `write:repository` scope so agents can push branches and open pull requests.
- Gitea refuses to run as root.
  The script runs admin commands with `su git -s /bin/sh -c "gitea ..."`.
- Workspaces are immutable and snapshotted once.
  A later push to the repository does not change an existing workspace.
  Create a new workspace to pick up new commits.

## Related

- [Credential injection](../explanation/credential-injection.md)
- [Multi-agent and multi-tenant design](../explanation/multi-agent-multitenancy.md)
