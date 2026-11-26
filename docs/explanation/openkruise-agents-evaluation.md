# OpenKruise Agents: what it provides and how it relates to this project

This page evaluates [openkruise/agents](https://github.com/openkruise/agents) against this project's stack (AX on Agent Substrate, with gVisor sandboxes, an egress gateway and a durable `/workspace`).
The question is whether it complements the stack or replaces a component.

Source: the repository's `README.md`, `roadmap.md`, `CHANGELOG.md` (v0.6.0), `config/crd/bases`, `docs/proposals` and `examples/`, read at `main` on 2026-11-25.
Nothing from OpenKruise was installed or run for this page, so every statement about behavior comes from its documentation, not from a test.

## What it is

OpenKruise Agents is a CNCF sub-project of OpenKruise.
It manages AI-agent sandboxes as Kubernetes workloads and is vendor-neutral.
Its README states four target workloads:

1. Isolated tool environments for agents.
2. Persistent, network-reachable notebooks and dev workspaces.
3. Reinforcement-learning jobs with a human in the loop.
4. Big-data training jobs that need fast startup.

## What it provides

| Area              | Capability                                                                                                                        | Main objects or components                                                                       |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Sandbox lifecycle | A sandbox is a Pod-backed custom resource. Warm pools, claims, templates, rolling update, in-place resize, autoscaling.           | `Sandbox`, `SandboxSet`, `SandboxClaim`, `SandboxTemplate`, `PoolAutoscaler`, `SandboxUpdateOps` |
| Pause and resume  | Pause strategies Stop, Snapshot and CloudDisk. Checkpoints with filesystem persistence. Auto-pause. Wake on traffic.              | `Checkpoint`, `Commit` (image commit with nerdctl)                                               |
| API surface       | Kubernetes CRDs and an E2B-compatible API and SDK. OpenSandbox and Substrate adapters are in progress.                            | `sandbox-manager`, `okactl` CLI                                                                  |
| Data plane        | A gateway routes by sandbox ID. An in-sandbox `agent-runtime` (envd-compatible) offers commands and file transfer.                | `sandbox-gateway`, `agent-runtime`                                                               |
| Network policy    | Declared egress policy at tenant and cluster scope. L7 rules, header manipulation, token transformation, MCP tool access control. | `TrafficPolicy`, `GlobalTrafficPolicy`, `SecurityProfile`                                        |
| Identity          | Per-sandbox short-lived tokens. User-delegated OAuth (GitHub 3LO) through an identity provider.                                   | `AgentIdentity`, `AgentRole`, `CredentialProvider`, `agent-identity-provider`                    |
| Storage           | Dynamic CSI mounts (OSS), with no manual sidecar setup.                                                                           | CSI integration                                                                                  |
| Observability     | Control-plane metrics and OpenTelemetry tracing from request to controller.                                                       | tracing and metrics packages                                                                     |
| Examples          | Code interpreter, desktop, OpenClaw and Claude Code on a warm pool.                                                               | `examples/`                                                                                      |

Isolation level is the runtime's choice.
The sandbox is an ordinary Pod, so it is as strong as the `RuntimeClass` the cluster gives it.
The roadmap lists "Kata/gvisor/kuasar best practice" as not started.

## Where it overlaps with this stack

| Concern              | This project (AX + Substrate)                                         | OpenKruise Agents                                                                                                                                     |
| -------------------- | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Unit of work         | `Task` (an Actor, not a Pod)                                          | `Sandbox` (a Pod)                                                                                                                                     |
| Warm capacity        | `WorkerPool` of pre-started gVisor worker pods                        | `SandboxSet` warm pool of Pods                                                                                                                        |
| Suspend and restore  | Substrate `runsc` checkpoint, restored on any free worker             | Pause strategies, `Checkpoint` and `Commit`. Memory and GPU state are claimed in the README. Filesystem persistence is "experimental" in the roadmap. |
| Egress control       | `Gateway` with host allowlist and `replaceHeaders` in `atenet-egress` | `TrafficPolicy` and `SecurityProfile` with header manipulation and token transformation                                                               |
| Credential injection | Secret with `ax.io/credential=true`, injected by the gateway          | `CredentialProvider`, `AgentIdentity` and header rules                                                                                                |
| Tenancy              | Substrate atespace                                                    | Kubernetes namespaces plus identity and RBAC objects                                                                                                  |
| Agent-facing API     | `ax` CLI, gRPC                                                        | E2B SDK, CRDs, `okactl`                                                                                                                               |
| Task semantics       | Workspace preparation, command, `Completed` state, `ax ssh`           | None found. A sandbox is an environment. The caller drives it.                                                                                        |

## Complement, replacement, or neither

**It does not replace AX.**
AX models a task: a workspace to prepare once, a command to run and a completion state.
OpenKruise models a sandbox that a client (usually through the E2B SDK) creates and drives.
The `Task` and `Workspace` workflow in this project has no OpenKruise equivalent.

**It can replace the Substrate layer, but only by losing what Substrate was chosen for.**
Both provide warm pools and pause/resume.
The differences that matter here:

- Substrate runs the sandbox in gVisor by design and treats actors as mutually hostile.
  OpenKruise leaves isolation to the cluster's runtime class, so gVisor would be a configuration you own.
- Substrate keeps high-churn actor state in PostgreSQL and avoids etcd load.
  OpenKruise stores each sandbox as a custom resource, so scale is bounded by the Kubernetes API.
  It mitigates this with its own gateway and peer cache, but the objects still live in etcd.
- Substrate's restore of process memory onto a different worker is documented.
  OpenKruise's equivalent is partly experimental.

**It can replace the egress and credential piece.**
`TrafficPolicy` and `SecurityProfile` cover the same job as `Gateway` and `replaceHeaders`, with more features (L7 rules, MCP tool control, per-sandbox identity).
This is the strongest overlap, and the part most likely to add value.
It cannot be used on its own, though: it is enforced by the OpenKruise gateway and runtime, not by `atenet-egress`.

**The two projects are converging.**
The OpenKruise roadmap lists "Implement Substrate backend adaptation" (in progress).
The README also says it stays compatible with SIG Agent-Sandbox.
If that adapter ships, OpenKruise becomes a front end (E2B API, warm pool, policy, identity) over Substrate.
In that case it would sit beside or in place of AX, with Substrate kept as the runtime.
Its status and scope are unknown, so this is a watch item, not a plan.

## Options

| Option                                                    | Effort  | Value                                                                                        | Risk                                                                                             |
| --------------------------------------------------------- | ------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| A. Keep the stack as is                                   | None    | Task semantics, gVisor and snapshots already verified here                                   | None                                                                                             |
| B. Borrow ideas only                                      | Low     | Per-sandbox identity, token rotation and MCP tool control as designs for the credential work | None                                                                                             |
| C. Run OpenKruise side by side on a second runtime        | Medium  | Compare the E2B-driven model and its policy objects with AX tasks                            | Two stacks to operate. Isolation must be configured separately.                                  |
| D. Replace AX and Substrate with OpenKruise               | High    | One CNCF project, E2B ecosystem                                                              | Loses `Task` semantics, built-in gVisor and verified snapshots. Rewrites every agent definition. |
| E. Adopt OpenKruise over Substrate once the adapter ships | Unknown | E2B API and warm-pool management on top of the current runtime                               | Depends on an unreleased adapter                                                                 |

## Recommendation

Do not replace a component now.
Choose A, with B as input to the existing [credential injection](credential-injection.md) and [multi-tenant](multi-agent-multitenancy.md) designs.
Re-evaluate E when the Substrate adapter is released.
If a comparison is wanted sooner, run C on a separate cluster using the Claude Code example, which is the closest to this project's OpenCode task.

## Questions worth answering before any adoption

- Does the Substrate adapter keep Substrate's actor model, or only use it as a pool of Pods?
- Can `TrafficPolicy` header manipulation inject a Secret-backed key without the sandbox seeing it? The proposal documents static header values and identity headers. A Secret reference was not confirmed.
- Which `RuntimeClass` options have been tested with the warm pool? The roadmap says gVisor guidance is not started.
- What is the pause/resume guarantee for process memory with the default pause strategy?
- How does it behave with many short-lived sandboxes, given that each is a custom resource?

## Sources

- [openkruise/agents README](https://github.com/openkruise/agents/blob/master/README.md)
- [Roadmap](https://github.com/openkruise/agents/blob/master/roadmap.md)
- [Changelog v0.6.0](https://github.com/openkruise/agents/blob/master/CHANGELOG.md)
- Proposals: traffic policy and security profile, agent identity and user-delegated credentials, sandbox auto-pause, sandbox commit (under `docs/proposals`)
- [How AX and Agent Substrate work together](ax-and-substrate.md)
