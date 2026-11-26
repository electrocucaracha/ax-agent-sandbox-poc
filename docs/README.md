# Documentation

This documentation covers a project that runs coding agents from multiple tenants on shared infrastructure,
using Agent Substrate (gVisor sandboxes), Google AX (orchestration) and a local kind cluster.
For a one-page overview, see the [project README](../README.md).

## Find what you need

| You want to...                                             | Read                                                                           |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Format, lint and test Python scripts                       | [Python development](../README.md#python-development)                          |
| Run your first sandboxed agent task                        | [Tutorial: run your first sandboxed task](tutorials/first-task.md)             |
| Point the agent at a real LLM endpoint                     | [Use a real LLM endpoint](how-to/use-real-llm-endpoint.md)                     |
| Trust a private certificate authority                      | [Trust a private CA](how-to/trust-private-ca.md)                               |
| Cut token use with rtk, Headroom, Engram or Graphify       | [Enable token-saving tools](how-to/enable-token-saving-tools.md)               |
| Run a different agent CLI                                  | [Plug in another agent](how-to/plug-in-another-agent.md)                       |
| Fix an error                                               | [Troubleshoot](how-to/troubleshoot.md)                                         |
| Run several agents per tenant                              | [Run the team demo](how-to/run-team-demo.md)                                   |
| Run the team demo against an external Ollama server        | [Team demo with Ollama](how-to/run-team-demo-with-ollama.md)                   |
| Host repositories on an in-cluster git server              | [Host repositories](how-to/host-repositories-with-git-server.md)               |
| Look up a script, variable or file                         | [Scripts and configuration reference](reference/scripts-and-configuration.md)  |
| See what `ax get` and `ax describe` print                  | [AX CLI output reference](reference/ax-cli-output.md)                          |
| Look up components, resources and roles                    | [Components and roles](reference/components-and-roles.md)                      |
| Follow one run end to end                                  | [How it all works together](explanation/how-it-works-end-to-end.md)            |
| Understand the team demo with diagrams and analogies       | [The team demo, explained](explanation/team-demo-explained.md)                 |
| Understand how AX and Substrate work together              | [How AX and Agent Substrate work together](explanation/ax-and-substrate.md)    |
| Evaluate OpenKruise Agents as a complement or replacement  | [OpenKruise Agents evaluation](explanation/openkruise-agents-evaluation.md)    |
| Understand this project's design                           | [Architecture](explanation/architecture.md)                                    |
| See how multiple agents and tenants fit together           | [Multi-agent and multi-tenant design](explanation/multi-agent-multitenancy.md) |
| Understand why credentials stay out of the sandbox         | [Credential injection](explanation/credential-injection.md)                    |
| See what the token-saving tools achieved                   | [Token-saving findings](explanation/token-saving-findings.md)                  |
| Improve agent, skill and tool-use definitions safely       | [Self-improvement procedure](how-to/self-improve-agent-definitions.md)         |
| Review self-improvement research and integration decisions | [Resource catalog](explanation/self-improvement-catalog.md)                    |
| Inspect measured improvement and rejected candidates       | [Self-improvement findings](explanation/self-improvement-findings.md)          |
| Check the matched replay and fresh team-run evidence       | [Runtime-validation report](explanation/runtime-validation-report.md)          |

## Status

Every claim in these pages comes from a run on this project.
Where a result comes from a single run, the page says so.

Not tested: more than one agent per worker,
a long-running session on a large repository, memory sharing across tasks, and any agent other than OpenCode.
