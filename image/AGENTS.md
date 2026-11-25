# Shell commands

Always prefix shell commands with `rtk` (for example `rtk git log`, `rtk git status`, `rtk ls`, `rtk find`, `rtk grep`).
`rtk` returns the same information with compressed output.

# Code navigation

A prebuilt code graph of the repository at /opt/sample-repo is at /opt/graph/graphify-out/graph.json.
Before grepping or reading many files, query it:

- `graphify explain "<symbol>" --graph /opt/graph/graphify-out/graph.json` shows where a symbol is defined and what calls or inherits from it.
- `graphify path "<A>" "<B>" --graph /opt/graph/graphify-out/graph.json` shows how two symbols connect.

Then read only the specific files and lines it points to.

# Memory

The `engram` MCP server stores durable notes in /workspace/home.
Save decisions and findings there, and search it before starting work that may repeat earlier work.
