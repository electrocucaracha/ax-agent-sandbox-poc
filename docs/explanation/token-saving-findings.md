# Token-saving findings

This page records what four token-saving tools did in this project,
and what the results do and do not show.
To turn a tool on, see [Enable token-saving tools](../how-to/enable-token-saving-tools.md).

## Method

Each test used the same OpenCode image and one model through a real Anthropic-format gateway.
Token counts come from `opencode stats`, summing input, cache read, cache write and output tokens.
Every number below is from a **single run**.
LLM output varies between runs, so repeat a test before you rely on it.

## Where each tool sits

```mermaid
flowchart LR
    subgraph sbx["Sandbox"]
        agent["OpenCode"]
        rtk["rtk<br/>shell output"]
        eng["Engram<br/>MCP memory"]
        gfy["Graphify<br/>code graph file"]
    end
    hr["Headroom proxy<br/>(in cluster)"]
    egress["atenet-egress"]
    llm([LLM])

    agent -->|runs commands| rtk
    agent -->|MCP| eng
    agent -->|graphify explain, path| gfy
    agent --> egress
    egress -->|"via Headroom (optional)"| hr
    hr --> llm
    egress -->|direct| llm
```

rtk, Engram and Graphify run inside the sandbox and shrink what the agent reads or re-discovers.
Headroom runs outside it and shrinks the request in transit.

## Summary

| Tool     | What it does                   | Works in the sandbox | Measured effect                                              |
| -------- | ------------------------------ | -------------------- | ------------------------------------------------------------ |
| rtk      | Compresses shell output        | Yes                  | No saving on the test; 38K to 43K tokens                     |
| Headroom | Compresses requests in a proxy | Yes                  | About 2.5% saving (423 of 16.8K tokens)                      |
| Engram   | Persistent memory over MCP     | Yes                  | Recall across sessions works; adds about 27 tool definitions |
| Graphify | Code graph for navigation      | Yes                  | About 28% fewer tokens and 58% fewer tool calls              |

## rtk

On a demo repository, the prompt asked the agent to run `git log --stat` and count commits for a file.

| Run         | Tokens    | Answer  |
| ----------- | --------- | ------- |
| Without rtk | about 38K | Correct |
| With rtk    | about 43K | Correct |

`rtk git log --stat` cut the output from 30 KB to 2.5 KB but showed only 10 commits.
The agent then reran plain `git log --stat`, so it paid for both.
rtk is likely to help more on test runs and `git status`, where the first compressed answer suffices.
That was not tested.

## Headroom

The request path worked and the answer was correct.
Savings were small because the large input was plain-text `git log` output,
which Headroom's router left alone.
Token mode and cache mode gave the same result.
Headroom targets repeated JSON, logs and large files.
Test it on that kind of workload.
It also sees the real API key.

## Engram

In one task, session 1 saved a fact with `engram_mem_save`.
Session 2, started separately in the same task, recalled it with `engram_mem_search`.
A session used about 33K tokens, partly because Engram adds 27 tool definitions to each request.
Memory across different tasks needs a shared store that this project does not set up.
Persistence across suspend and resume was not tested.

## Graphify

The question was a cross-file lookup on `pallets/click`: classes that inherit from `Command`,
and callers of `Context.invoke`.
The graph held 3.5K nodes and 6.8K edges.

| Run      | Tool calls | Output tokens | Total tokens |
| -------- | ---------- | ------------- | ------------ |
| Baseline | 19         | 2.8K          | about 72K    |
| Graphify | 8          | 0.9K          | about 52K    |

Accuracy did not clearly improve.
The graphify run listed only 2 of the direct `Command` subclasses.
Treat the graph as a navigation aid and verify answers.

## What is still open

- Repeat each test several times to measure variance.
- Test rtk and Headroom on noisy workloads such as test runs and JSON output.
- Test Engram across suspend and resume, and across tasks.
- Compare answer accuracy with a fixed set of questions.
