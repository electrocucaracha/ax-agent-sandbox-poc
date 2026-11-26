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
See [`.env.example`](../../.env.example) for a safe local settings sample.
The image phase updates image settings in ignored `.env.opencode` and preserves other entries.
Set `IMAGE_SOURCE=external` and `OPENCODE_IMAGE` to use a compatible prebuilt image; `IMAGE_SOURCE=local` forces a local rebuild.

| Script                    | Purpose                                                                                                                                                                                                                               |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `00-preflight.sh [--fix]` | Checks tools, container engine, memory and kernel. `--fix` resizes the Podman VM.                                                                                                                                                     |
| `01-install-ax.sh`        | Installs a pinned `ax` into `~/.ax/bin`.                                                                                                                                                                                              |
| `02-start-cluster.sh`     | Runs `ax local start`, then applies the gVisor asset fix.                                                                                                                                                                             |
| `02b-fix-gvisor-asset.sh` | Uploads the gVisor tarball to the in-cluster object store.                                                                                                                                                                            |
| `03-build-push-image.sh`  | Uses a prebuilt image for `IMAGE_SOURCE=external`; otherwise builds and pushes locally.                                                                                                                                               |
| `05-mock-llm.sh`          | Deploys a TLS mock LLM, generates a CA in `certs/` and patches egress trust.                                                                                                                                                          |
| `06-ollama.sh`            | Checks an external Ollama server's model list at `${OLLAMA_URL}/api/tags`. Loads no model. Env: `OLLAMA_URL` (required, HTTPS), `OLLAMA_MODEL` (default `qwen2.5-coder:7b`, probe only), `CURL_CA_BUNDLE` (optional local CA bundle). |
| `07-headroom.sh`          | Deploys the Headroom proxy. Requires `UPSTREAM_URL`.                                                                                                                                                                                  |
| `09-git-server.sh`        | Deploys Gitea (stand-in for Forgejo) with TLS and an admin user.                                                                                                                                                                      |
| `10-team-demo.sh`         | Runs one epic with a team of agents in parallel, delivered as PRs.                                                                                                                                                                    |
| `11-token-benchmark.py`   | Measures repeated baseline/rtk context-token usage in one sandbox; `--headroom` adds a direct/proxy comparison.                                                                                                                       |
| `12-self-improve.py`      | Evaluates additive role/skill/tool-use instruction changes in AX, records paired results, and optionally promotes holdout-improving candidates. See [usage and gates](../how-to/self-improve-agent-definitions.md).                   |
| `99-teardown.sh`          | Deletes the cluster.                                                                                                                                                                                                                  |

## Python development checks

[`pyproject.toml`](../../pyproject.toml) defines the Python 3.10 syntax target,
88-character Black/isort formatting width, Ruff error and modernization rules,
and Google-style docstring checks.
Descriptive test methods are exempt from mandatory docstrings.
The `dev` dependency group in [`pyproject.toml`](../../pyproject.toml) pins
development tools; runtime scripts still use only the standard library and
declare no dependencies in their PEP 723 `# /// script` metadata.

| Make target     | Purpose                                                       |
| --------------- | ------------------------------------------------------------- |
| `format-python` | Applies safe Ruff fixes, isort ordering and Black formatting  |
| `lint-python`   | Checks Black, isort and Ruff without editing files            |
| `test-python`   | Runs unittest discovery, including offline docstring examples |
| `check-python`  | Runs lint checks and tests                                    |

The `PYTHON` Make variable defaults to `.venv/bin/python`.
[`tests/test_doctests.py`](../../tests/test_doctests.py) loads script and runtime
helper docstrings without starting services or reading provider credentials.
[`python.yml`](../../.github/workflows/python.yml) runs the same checks in CI.
See [development setup](../../README.md#python-development).

## Evidence replay validation

The validation-only `tests/replay_evidence.py` compares a fixed original and
admitted evidence skill without optimization or promotion.
It records direct-model and actual OpenCode accuracy, latency and token usage.
Its arguments are `--output <new-directory>` and `--repetitions <1-5>`.
The default is three repetitions.
See [the replay procedure](../how-to/self-improve-agent-definitions.md#replay-the-admitted-evidence-skill-without-optimizing).

## `10-team-demo.sh` variables

| Variable                 | Default                                                                         | Description                                                                                                                                                                                                                                                                              |
| ------------------------ | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `LLM_API_KEY`            | a fake key per tenant; `ollama` when `OLLAMA_URL` is selected                   | Key stored in each tenant's Secret `llm-key`. `LITELLM_PROXY_API_KEY` takes precedence when set.                                                                                                                                                                                         |
| `LLM_HOST`               | `mock-llm.default.svc.cluster.local`                                            | Upstream hostname, optionally with a base-path prefix; the hostname is added to the Gateway allowlist. Ignored when `LITELLM_PROXY_API_BASE` is set.                                                                                                                                     |
| `LLM_PATH`               | `/v1`                                                                           | Base path appended to `https://<LLM_HOST>`. Ignored when `LITELLM_PROXY_API_BASE` is set.                                                                                                                                                                                                |
| `LITELLM_PROXY_API_BASE` | unset                                                                           | HTTPS base URL for the existing LiteLLM setup; overrides `LLM_HOST`/`LLM_PATH` and is normalized for the Anthropic endpoint.                                                                                                                                                             |
| `OLLAMA_URL`             | unset                                                                           | External Ollama HTTPS base URL, without `/v1`. Derives `LLM_HOST`/`LLM_PATH` and selects Ollama config/key defaults. An explicit `LITELLM_PROXY_API_BASE` takes precedence and bypasses those defaults. See [Connect an external Ollama server](../how-to/run-team-demo-with-ollama.md). |
| `LLM_MODEL_ID`           | unset                                                                           | Optional provider-facing model name override. Falls back to the model portion of `LITELLM_PROXY_MODEL=anthropic/<model>`.                                                                                                                                                                |
| `LLM_AUTH_MODE`          | `both`                                                                          | Use `x-api-key` to remove the bearer header for API-key-only providers.                                                                                                                                                                                                                  |
| `LLM_EXTRA_HEADERS_JSON` | unset                                                                           | Optional JSON object of extra provider headers; values must be strings. `CHANGELOG_LITELLM_HEADERS_JSON` takes precedence; `LITELLM_EXTRA_HEADERS_JSON` is a fallback alias.                                                                                                             |
| `OC_CONFIG`              | `/opt/opencode.json`; `/opt/opencode.ollama.json` when `OLLAMA_URL` is selected | OpenCode config inside the image. An explicit value overrides either default.                                                                                                                                                                                                            |
| `GIT_ADMIN_PASS`         | `admin-pass-123`                                                                | Git admin password (also used by `09-git-server.sh`).                                                                                                                                                                                                                                    |
| `HOLD_SECONDS`           | `3 * EPIC_TIMEOUT + MUTATION_TIMEOUT + 300`                                     | Seconds each task stays alive after the agent exits; the default covers all four waves and final checks.                                                                                                                                                                                 |
| `MUTATION_MEMORY`        | `2Gi`                                                                           | Memory limit for mutation only; other tasks inherit the workspace profile.                                                                                                                                                                                                               |
| `MUTATION_TIMEOUT`       | `3600`                                                                          | Overall mutation-wave deadline, including agent setup and reporting; individual mutmut invocations are limited to three minutes.                                                                                                                                                         |
| `WORKERS`                | initial tasks + builder-role count (`10`)                                       | Size of the worker pool; mutation runs separately.                                                                                                                                                                                                                                       |
| `EPIC_TIMEOUT`           | `1800`                                                                          | Seconds to wait for each non-mutation wave to finish.                                                                                                                                                                                                                                    |
| `SAMPLE_REPO_URL`        | `https://github.com/pallets/click.git`                                          | Seed repository cloned when `image/sample-repo/` is absent.                                                                                                                                                                                                                              |
| `SAMPLE_REPO_REF`        | `8.1.8`                                                                         | Branch or tag used for that clone.                                                                                                                                                                                                                                                       |

Each task writes agent output to `/workspace/out.log`.
The `ROLES` array in the script lists `wave|tenant|task|spec` entries.
The spec is `epic:<role>` (epic, team rules and `agents/<role>.md`), `prompt:<file>` (`agents/<file>.md` as is) or `script:<file>` (`agents/<file>.sh`, no LLM).
Wave 0 triages the epic while the plumbing and beta tasks run.
Wave 1 runs the six independent builders, wave 2 runs mutation after their branches exist,
and wave 3 runs the reviewers. Builder tasks are deleted between waves to free their workers.
A task writes `/workspace/done` when its command ends, which the script polls.
The script base64-encodes the file into the `AGENT_PROMPT_B64` task variable.
The task decodes it to `/workspace/prompt.md` and attaches it with `opencode run -f`.
Base64 avoids prompt quoting issues, but AX limits the encoded launch
configuration to 31,744 bytes. The self-improvement runner compresses its bundle
to stay within that limit.

## `03-build-push-image.sh` variables

| Variable       | Default                          | Description                                                                                                    |
| -------------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `IMAGE_NAME`   | `opencode-task`                  | Image name in the local registry.                                                                              |
| `ENV_VAR`      | `OPENCODE_IMAGE`                 | Variable name written to the env file.                                                                         |
| `ENV_FILE`     | `.env.opencode`                  | File that receives the digest-pinned reference; existing entries are preserved.                                |
| `BASE_IMAGE`   | `docker.io/library/node:22-slim` | Base image.                                                                                                    |
| `IMAGE_SOURCE` | `local` or `external`            | Selects build mode; defaults local without an image reference, external when one exists without a mode marker. |

A prebuilt image must contain the OpenCode runtime and project tool configuration and be pullable by the Substrate workers.

## Image files

| File                            | Purpose                                                                                       |
| ------------------------------- | --------------------------------------------------------------------------------------------- |
| `Dockerfile`                    | Single build file. OpenCode, Graphify, rtk, Engram, configs, demo repo and sample graph.      |
| `resources/headroom/Dockerfile` | Headroom proxy with a `socat` TLS front. It is a shared service, not part of the agent image. |
| `opencode.json`                 | OpenAI-compatible provider, for the mock.                                                     |
| `opencode.anthropic.json`       | Anthropic-format provider.                                                                    |
| `opencode.local.json`           | Git-ignored copy with private headers.                                                        |
| `AGENTS.md`                     | Instructions for rtk, Graphify and Engram, loaded by the config.                              |
| `make-demo-repo.sh`             | Builds `/opt/demo-repo` with 120 commits.                                                     |

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

| Path                         | Purpose                                                                                                                                                                                                          |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `resources/team/`            | Kustomization: Gateway (git and LLM hosts, header injection) and a Workspace.                                                                                                                                    |
| `resources/task/`            | Kustomization: a Task that mounts the workspace and runs one role.                                                                                                                                               |
| `resources/mock-llm/`        | Kustomization for the mock LLM; `server.py` logs the received `Authorization`.                                                                                                                                   |
| `resources/git-server/`      | Kustomization for Gitea.                                                                                                                                                                                         |
| `resources/headroom/`        | Kustomization and Dockerfile for the Headroom proxy.                                                                                                                                                             |
| `resources/egress-trust/`    | JSON patch that mounts the extra CA bundle into the egress gateway.                                                                                                                                              |
| `scripts/issues.py`          | Click CLI (run with `uv run --script`) with `epic`, `list`, `body`, and `fallback` subcommands for the team-demo issues. Verifies the git server certificate against `certs/ca.crt`; `-v` logs each API request. |
| `image/opencode.ollama.json` | OpenCode config for Ollama (`OC_CONFIG=/opt/opencode.ollama.json`).                                                                                                                                              |

## Credential options

| Method                                       | Visible to the sandbox | Notes                                          |
| -------------------------------------------- | ---------------------- | ---------------------------------------------- |
| Egress `replaceHeaders` with `ate-secret://` | No                     | Recommended. Header-based auth on HTTPS hosts. |
| `Model.spec.secretKey`                       | No                     | For AX-managed runners, not custom images.     |
| `spec.env`                                   | Yes                    | Plain text in the Task spec.                   |
| Workspace `setup.files`                      | Yes                    | Plain text in the manifest and snapshots.      |
| `ax ssh` and write a file                    | Yes                    | Manual and not repeatable.                     |
