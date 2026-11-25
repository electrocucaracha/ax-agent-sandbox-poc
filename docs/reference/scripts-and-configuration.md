# Scripts and configuration reference

## Versions

| Component       | Version                      |
| --------------- | ---------------------------- |
| `ax` CLI        | v0.4.0-rc.1 (API `v1alpha1`) |
| Agent Substrate | v1.0.0                       |
| kind            | v0.33.0                      |
| Podman (tested) | 6.1.4                        |

Both AX and Substrate are alpha software.
The scripts pin the versions.

## Scripts

All scripts are in `scripts/`.

`scripts/main.sh` runs the scripts below as named phases, in the order you give.
It validates every phase name before it runs any, and `DEBUG=true` traces each command.

```bash
scripts/main.sh list                 # show phases and the default set
scripts/main.sh                      # preflight install cluster image mock-llm git-server team-demo
scripts/main.sh image agent          # chosen phases
PHASES="git-server multi-tenant" scripts/main.sh
```

Phases: `preflight`, `install`, `cluster`, `image`, `mock-llm`,
`headroom`, `git-server`, `team-demo`, `team-demo-down`, `teardown`.
Environment variables such as `LLM_HOST`, `LLM_API_KEY` and `UPSTREAM_URL` pass through to the scripts.
`_utils.sh` holds the shared log helpers.

| Script                    | Purpose                                                                                      |
| ------------------------- | -------------------------------------------------------------------------------------------- |
| `00-preflight.sh [--fix]` | Checks tools, container engine, memory and kernel. `--fix` resizes the Podman VM.            |
| `01-install-ax.sh`        | Installs a pinned `ax` into `~/.ax/bin`.                                                     |
| `02-start-cluster.sh`     | Runs `ax local start`, then applies the gVisor asset fix.                                    |
| `02b-fix-gvisor-asset.sh` | Uploads the gVisor tarball to the in-cluster object store.                                   |
| `03-build-push-image.sh`  | Builds an image and pushes it to a registry on the `kind` network.                           |
| `05-mock-llm.sh`          | Deploys a TLS mock LLM, generates a CA in `certs/` and patches egress trust.                 |
| `06-ollama.sh`            | Deploys a TLS proxy to an Ollama server on the host. Env: `OLLAMA_MODEL`, `OLLAMA_UPSTREAM`. |
| `07-headroom.sh`          | Deploys the Headroom proxy. Requires `UPSTREAM_URL`.                                         |
| `09-git-server.sh`        | Deploys Gitea (stand-in for Forgejo) with TLS and an admin user.                             |
| `10-team-demo.sh`         | Runs one epic with a team of agents in parallel, delivered as PRs.                           |
| `99-teardown.sh`          | Deletes the cluster.                                                                         |

## `10-team-demo.sh` variables

| Variable         | Default                              | Description                                           |
| ---------------- | ------------------------------------ | ----------------------------------------------------- |
| `LLM_API_KEY`    | a fake key per tenant                | Real key, stored in each tenant's Secret `llm-key`.   |
| `LLM_HOST`       | `mock-llm.default.svc.cluster.local` | Upstream host, added to the Gateway allowlist.        |
| `LLM_PATH`       | `/v1`                                | Base path appended to `https://<LLM_HOST>`.           |
| `OC_CONFIG`      | `/opt/opencode.json`                 | OpenCode config inside the image.                     |
| `GIT_ADMIN_PASS` | `admin-pass-123`                     | Git admin password (also used by `09-git-server.sh`). |
| `HOLD_SECONDS`   | `900`                                | Seconds each task stays alive after the agent exits.  |
| `WORKERS`        | tasks in waves 0 and 1               | Size of the worker pool.                              |
| `EPIC_TIMEOUT`   | `1800`                               | Seconds to wait for each wave to finish.              |

Each task writes agent output to `/workspace/out.log`.
The `ROLES` array in the script lists `wave|tenant|task|spec` entries.
The spec is `epic:<role>` (epic, team rules and `agents/<role>.md`), `prompt:<file>` (`agents/<file>.md` as is) or `script:<file>` (`agents/<file>.sh`, no LLM).
Wave 0 and 1 start together, and wave 2 starts when wave 1 has finished.
A task writes `/workspace/done` when its command ends, which the script polls.
The script base64-encodes the file into the `AGENT_PROMPT_B64` task variable.
The task decodes it to `/workspace/prompt.md` and attaches it with `opencode run -f`.
Prompt files have no quoting limits.

## `03-build-push-image.sh` variables

| Variable     | Default                          | Description                                     |
| ------------ | -------------------------------- | ----------------------------------------------- |
| `IMAGE_NAME` | `opencode-task`                  | Image name in the local registry.               |
| `ENV_VAR`    | `OPENCODE_IMAGE`                 | Variable name written to the env file.          |
| `ENV_FILE`   | `.env.opencode`                  | File that receives the digest-pinned reference. |
| `BASE_IMAGE` | `docker.io/library/node:22-slim` | Base image.                                     |

## Image files

| File                      | Purpose                                                                                       |
| ------------------------- | --------------------------------------------------------------------------------------------- |
| `Dockerfile`              | Single build file. OpenCode, Graphify, rtk, Engram, configs, demo repo and sample graph.      |
| `resources/headroom/Dockerfile` | Headroom proxy with a `socat` TLS front. It is a shared service, not part of the agent image. |
| `opencode.json`           | OpenAI-compatible provider, for the mock.                                                     |
| `opencode.anthropic.json` | Anthropic-format provider.                                                                    |
| `opencode.local.json`     | Git-ignored copy with private headers.                                                        |
| `AGENTS.md`               | Instructions for rtk, Graphify and Engram, loaded by the config.                              |
| `make-demo-repo.sh`       | Builds `/opt/demo-repo` with 120 commits.                                                     |

Git ignores `certs/`, `.env.*`, the `rtk` and `engram` binaries,
`opencode.local*.json`, `image/sample-repo/` and `image/graph/`.

## Resources and kustomize

All Kubernetes and AX YAML lives in `resources/`, one kustomization per component.
Scripts apply static ones with `kubectl apply -k resources/<name>`.
Ones with run-time values (tenant, image, upstream URL) use `${PLACEHOLDERS}`.
The `render` helper in `scripts/_utils.sh` builds the kustomization with `kubectl kustomize` and then fills the listed variables with `envsubst`.
Preview any component with `kubectl kustomize resources/<name>`.
TLS Secrets stay in the scripts, because they are generated from `certs/` at run time.
Placeholders must be strings after rendering: kustomize rewrites quoting, so a quoted `"${PORT}"` becomes an integer once substituted.

## Other files

| Path                            | Purpose                                                                           |
| ------------------------------- | --------------------------------------------------------------------------------- |
| `resources/team/`               | Kustomization: Gateway (git and LLM hosts, header injection) and a Workspace.     |
| `resources/task/`               | Kustomization: a Task that mounts the workspace and runs one role.                |
| `resources/mock-llm/`           | Kustomization for the mock LLM; `server.py` logs the received `Authorization`.    |
| `resources/git-server/`         | Kustomization for Gitea.                                                          |
| `resources/ollama/`             | Kustomization and `server.py`: HTTPS-to-HTTP streaming proxy to the host's Ollama. |
| `resources/headroom/`           | Kustomization and Dockerfile for the Headroom proxy.                              |
| `resources/egress-trust/`       | JSON patch that mounts the extra CA bundle into the egress gateway.               |
| `scripts/issues.py`             | Creates the epic issue, lists `[role:<name>]` issues, and holds the fallback plan. |
| `image/opencode.ollama.json`    | OpenCode config for Ollama (`OC_CONFIG=/opt/opencode.ollama.json`).               |

## Credential options

| Method                                       | Visible to the sandbox | Notes                                          |
| -------------------------------------------- | ---------------------- | ---------------------------------------------- |
| Egress `replaceHeaders` with `ate-secret://` | No                     | Recommended. Header-based auth on HTTPS hosts. |
| `Model.spec.secretKey`                       | No                     | For AX-managed runners, not custom images.     |
| `spec.env`                                   | Yes                    | Plain text in the Task spec.                   |
| Workspace `setup.files`                      | Yes                    | Plain text in the manifest and snapshots.      |
| `ax ssh` and write a file                    | Yes                    | Manual and not repeatable.                     |
