# Components and roles reference

Every component in the stack, what it is responsible for, and where it runs.
For how they interact, see [How AX and Agent Substrate work together](../explanation/ax-and-substrate.md).

Source: upstream docs for AX `v0.4.0-rc.1` and Agent Substrate `v1.0.0`, checked against the pods and services in this project's `kind` cluster.

## Components

### Client side

| Component               | Role                                                                                                                         |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `ax` CLI                | Sends declarations (`apply`) and commands (`resume`, `suspend`, `ssh`, `delete`) to `ax-server`. Opens a local tunnel to it. |
| AX Studio (`ax studio`) | Local web UI for the same operations.                                                                                        |
| Scripts in this project | Build the cluster and image, create Secrets, and apply Gateway and Task manifests.                                           |

### AX (namespace `ax-system`)

| Component     | Role                                                                                                                                      |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `ax-server`   | AX control plane. Validates and stores resources, takes locks, and drives Substrate to match what you declared.                           |
| `ax-postgres` | AX database. Holds specs, metadata, AX-owned status and the leases behind distributed locks.                                              |
| `ax-runner`   | Runs inside the sandbox as PID 1. Receives the task and workspace, prepares `/workspace` once, starts your command and reports readiness. |

### Agent Substrate control plane (namespace `ate-system`)

| Component                 | Role                                                                                                                      |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `ate-api-server`          | Substrate API. Owns actors, templates and workers, schedules actors onto workers, and authorizes every call per atespace. |
| `ate-controller`          | Turns `WorkerPool` resources into worker pods.                                                                            |
| `ate-idp-server`          | Issues identity to actors.                                                                                                |
| `postgres`                | Substrate database for live actor and worker state.                                                                       |
| `rustfs`                  | S3-compatible object store for snapshots and sandbox assets.                                                              |
| `k8s-credential-provider` | Reads Kubernetes Secrets so the egress proxy can inject credentials.                                                      |

### Agent Substrate data plane

| Component       | Role                                                                                                                         |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `atelet`        | Per-node supervisor (DaemonSet). Restores, runs and checkpoints sandboxes, and moves snapshots to and from the object store. |
| `ateworker`     | The worker pod (namespace `ate-workers`, image `ateworker-gvisor`). Hosts the gVisor sandbox through `runsc`.                |
| `atenet-router` | Ingress proxy. Routes requests to an actor by the `ate-target-actor` header and resumes it if suspended.                     |
| `atenet-egress` | Egress proxy. Default-deny, host allowlist, TLS termination and header replacement.                                          |

### Observability (namespace `otel-system`)

`jaeger`, `prometheus` and an OpenTelemetry collector provide traces and metrics.

### Inside the sandbox

| Component          | Role                                                                       |
| ------------------ | -------------------------------------------------------------------------- |
| Agent (OpenCode)   | The coding agent. A normal program that the stack treats as untrusted.     |
| Token-saving tools | Optional helpers baked into the image: rtk, Headroom, Engram and Graphify. |
| `/workspace`       | Durable volume. Survives suspend and resume.                               |

## Resources

| Resource                      | Owned by               | Role                                                                                     |
| ----------------------------- | ---------------------- | ---------------------------------------------------------------------------------------- |
| `Task`                        | AX                     | A command to run, with an image, environment and a gateway.                              |
| `Workspace`                   | AX                     | Repositories, MCP servers and files to prepare for a task.                               |
| `Gateway`                     | AX                     | Egress rules: allowed hosts and header replacement.                                      |
| `Model`                       | AX                     | Provider settings plus a Secret reference.                                               |
| `WorkerPool`, `SandboxConfig` | Substrate (Kubernetes) | How many warm workers exist and which sandbox type they use.                             |
| `ActorTemplate`               | Substrate              | Immutable workload definition. Tasks with the same profile share one.                    |
| `Actor`                       | Substrate              | One sandboxed workload, running or suspended.                                            |
| `Worker`                      | Substrate              | A pod that can host an actor.                                                            |
| atespace                      | Substrate              | The tenant scope. Every AX resource lives in one, and Substrate authorizes per atespace. |

## Human and system roles

| Role                   | Does                                                                                                                              | Uses                                            |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Platform operator      | Installs AX and Substrate, sizes the `WorkerPool`, manages Secrets and trust bundles, and grants atespaces access to credentials. | `kubectl`, `ax install`, this project's scripts |
| Tenant user            | Declares tasks and gateways in their atespace and runs agents.                                                                    | `ax` CLI                                        |
| Agent                  | Does the coding work inside the sandbox. Holds no real credentials.                                                               | Files in `/workspace`, allowlisted hosts        |
| Control plane services | Act on behalf of the above, authenticated by service tokens and certificates.                                                     | Internal gRPC                                   |

The split matters for credentials.
The operator stores the real key in a Secret, the tenant references it from a `Gateway`, and the agent sees only a placeholder.
See [Credential injection](../explanation/credential-injection.md).

## Related

- [AX CLI output reference](ax-cli-output.md)
- [Scripts and configuration reference](scripts-and-configuration.md)
- [Multi-agent and multi-tenant design](../explanation/multi-agent-multitenancy.md)
