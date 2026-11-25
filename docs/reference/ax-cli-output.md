# AX CLI output reference

Sample output of the read-only `ax` commands, captured from this project's `kind` cluster with `ax v0.4.0-rc.1`.
Names, UIDs and digests are specific to that run, and formatting can change between versions.
Add `-a <atespace>` to any command to scope it to another atespace.

## ax get tasks

```text
$ ax get tasks
NAME          ATESPACE   STATE       ACTOR         AGE
stub-1        default    Completed   stub-1        2h
simple-task   default    Completed   simple-task   3h
```

| Column     | Meaning                                                                                                                  |
| ---------- | ------------------------------------------------------------------------------------------------------------------------ |
| `NAME`     | Task name, unique within the atespace.                                                                                   |
| `ATESPACE` | Tenant scope that owns the task. An atespace is Substrate's namespace-like grouping, and every AX resource lives in one. |
| `STATE`    | Task state. The CLI shortens the API value `TASK_STATE_COMPLETED` to `Completed`.                                        |
| `ACTOR`    | Name of the Substrate actor that runs the task.                                                                          |
| `AGE`      | Time since the task was created.                                                                                         |

A running task prints `Working` in `STATE`, and a suspended one prints `Suspended`.
In `-o yaml` these are `TASK_STATE_WORKING` and `TASK_STATE_COMPLETED`.

```text
$ ax -a alpha get tasks
NAME      ATESPACE   STATE       ACTOR     AGE
alpha-2   alpha      Working     alpha-2   47s
alpha-1   alpha      Suspended   alpha-1   48s
```

A running task's `Ready` condition has reason `TaskRunning` and message `Task is running and its workspace is ready`.

## ax get gateways

```text
$ ax get gateways
NAME          ATESPACE   EGRESS-RULES
opencode-gw   default    1
stub-gw       default    2
```

`EGRESS-RULES` counts the rules in the gateway.

## ax get workspaces and ax get models

Both print only a header when none exist, as in this project.

```text
$ ax get workspaces
NAME   ATESPACE   PHASE   GIT-REPOS   MCP-SERVERS

$ ax get models
NAME   ATESPACE   PROVIDER   MODEL
```

## ax describe task

```text
$ ax describe task stub-1
Name:         stub-1
Atespace:     default
UID:          e73bb438-660b-4dc2-a169-330c3ef62be8
State:        Completed
Actor:        stub-1
Actor UID:    abba9b00-a0f4-46e3-8748-3382eb5e5d74
Template:     default/ax-ae25fa523c07b8c6
Attempt:      1
Session ID:   e73bb438-660b-4dc2-a169-330c3ef62be8
Gateway:      stub-gw
Image:        10.89.2.3:5000/stub-task@sha256:acda4648...
Commands:     [sh -c mkdir -p $HOME && agent --version; sleep 240]
Outcome:      TASK_RESULT_SUCCEEDED (exitCode=0)
Output:
  agent-stub: args=--version
  ANTHROPIC_API_KEY=placeholder (placeholder expected)
  ...

Conditions:
  TYPE            STATUS  REASON         MESSAGE
  WorkspaceReady  True    SetupComplete  Workspace requires no setup
  Ready           False   Completed      task command completed
```

| Field                | Meaning                                                                                                                           |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `UID`                | AX's identifier for the task.                                                                                                     |
| `Actor`, `Actor UID` | The Substrate actor behind the task.                                                                                              |
| `Template`           | The Substrate `ActorTemplate` as `<atespace>/<name>`. The name is a hash of the profile, so tasks with the same profile share it. |
| `Attempt`            | Run attempt counter.                                                                                                              |
| `Session ID`         | Session identifier. It equals the task UID here.                                                                                  |
| `Gateway`            | The gateway that controls the task's egress.                                                                                      |
| `Outcome`            | Result and exit code of the command.                                                                                              |
| `Output`             | Captured output of the command.                                                                                                   |
| `Conditions`         | `WorkspaceReady` reports workspace setup. `Ready` is `False` here because the command finished.                                   |

## ax describe gateway

```text
$ ax describe gateway stub-gw
Name:         stub-gw
Atespace:     default
Egress Rules:
  - https: mock-llm.default.svc.cluster.local
  - https: github.com, api.github.com
```

## ax get task NAME -o yaml

`ax get task <name> -o yaml` prints the full resource, including the API state values.
The listing is trimmed to the main fields.

```yaml
apiVersion: ax.io/v1alpha1
kind: Task
metadata:
  name: stub-1
  atespace: default
spec:
  profile:
    image: 10.89.2.3:5000/stub-task@sha256:acda4648...
  commands: [sh, -c, "mkdir -p $HOME && agent --version; sleep 240"]
  env:
    - name: ANTHROPIC_API_KEY
      value: placeholder
  debug: true
  gateway:
    name: stub-gw
status:
  actor: stub-1
  ateTemplate:
    name: ax-ae25fa523c07b8c6
    atespace: default
  conditions:
    - type: Ready
      status: "False"
      reason: Completed
  state: TASK_STATE_COMPLETED
  outcome:
    result: TASK_RESULT_SUCCEEDED
```

The `spec` block is what you applied.
The `status` block is what AX reports back, combining its own records with the live actor state from Substrate.
See [How AX and Agent Substrate work together](../explanation/ax-and-substrate.md).

## ax ctx

```text
$ ax ctx
CURRENT  NAME      CLUSTER        AX TUNNEL
*        ax-local  kind-ax-local  127.0.0.1:53879 -> ax-system/ax-server (Healthy)
```

`AX TUNNEL` shows the local port forward to `ax-server` that the CLI opens for the active context.

## Related

- [Scripts and configuration reference](scripts-and-configuration.md)
- [Troubleshoot](../how-to/troubleshoot.md)
