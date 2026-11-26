# Troubleshoot

Diagnose common failures.

## Task and cluster errors

| Symptom                                      | Cause                                     | Fix                                        |
| -------------------------------------------- | ----------------------------------------- | ------------------------------------------ |
| `ax: command not found`                      | `~/.ax/bin` is not on `PATH`              | `export PATH="$HOME/.ax/bin:$PATH"`        |
| `ax ssh` says the task must be `Working`     | The task already finished                 | Set a larger `HOLD_SECONDS` and rerun.     |
| Task spec change rejected                    | Task specs are immutable                  | `ax delete task <name>`, then apply again. |
| Image pull fails                             | Task images must be pinned by digest      | Use the reference in the `.env.*` file.    |
| `podman run -v /tmp/...` fails with `statfs` | The Podman VM cannot mount that host path | Use a path under your home directory.      |

## Network and TLS errors

| Symptom                                                  | Cause                                      | Fix                                                                                        |
| -------------------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `Proxy refused to open a tunnel: 407` inside the sandbox | The agent downloaded a package at runtime  | Pre-install it in the image.                                                               |
| `407` when pushing the image                             | The host push went through a network proxy | `03-build-push-image.sh` pushes from inside the VM with `NO_PROXY` set to the registry IP. |
| Upstream certificate rejected                            | The egress gateway does not trust the CA   | [Trust a private CA](trust-private-ca.md).                                                 |

## LLM errors

| Symptom                                               | Cause                                                              | Fix                                                   |
| ----------------------------------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------- |
| `Tenant ... is not authorized for model ...`          | The key is valid but the model is not enabled for it               | Use a model your key can access, with the exact name. |
| `Failed to invoke endpoint` on `/v1/chat/completions` | The model is served in another API format                          | Try `/v1/messages` with the Anthropic provider.       |
| `The token was expected to have 3 parts`              | The gateway read a placeholder from a header that was not injected | Add that header to `replaceHeaders`.                  |

## Environment-specific problems

- **gVisor download blocked.**
  The atelet fetches gVisor from a `gs://` bucket.
  If your network blocks it, run `scripts/02b-fix-gvisor-asset.sh`.
  It downloads and verifies the tarball on the host, uploads it to the in-cluster object store,
  and registers a new SandboxConfig version.
- **Example image moved.**
  The stock example references a runner image that is no longer public.
  `01-install-ax.sh` patches it to the `ghcr.io` copy.
- **Git refuses a repository outside `/workspace`.**
  Run `git config --global --add safe.directory <path>` in the sandbox.
- **Agent cannot read outside the workspace.**
  Set `permission.external_directory` to `allow` in the OpenCode config.
  The provided configs already do.
