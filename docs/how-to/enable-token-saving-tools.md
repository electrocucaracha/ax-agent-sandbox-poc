# Enable token-saving tools

Turn on rtk, Headroom, Engram or Graphify for a sandboxed OpenCode task.
For measured results, see [Token-saving findings](../explanation/token-saving-findings.md).

Every tool must be installed in the image, because the sandbox cannot reach package registries.
The image has one config, `/opt/opencode.anthropic.json`, and one instruction file, `image/AGENTS.md`.
The config loads `AGENTS.md` and starts the Engram MCP server.
`AGENTS.md` has one section per tool (shell commands, code navigation, memory).
Remove a section, or its binary, to run without that tool.
For headers you cannot commit, use `opencode.local.json`.
Headroom is a cluster service: set `LLM_HOST` to route through it.

## rtk

rtk compresses shell command output.
The image includes the `rtk` binary, and the "Shell commands" section of `image/AGENTS.md` tells the agent to prefix commands with `rtk`.

1. Place a `linux/arm64` (or matching architecture) `rtk` binary at `image/rtk`.
2. Rebuild the image.
3. Run as usual.

The image also contains `/opt/demo-repo`, a 120-commit repository for measuring output size.

## Headroom

Headroom is a context-compression proxy that runs in the cluster.

1. Deploy it, pointing at your upstream:

   ```bash
   UPSTREAM_URL=https://llm.example.com/gateway scripts/07-headroom.sh
   ```

2. Run the task through it:

   ```bash
   LLM_HOST=headroom.default.svc.cluster.local LLM_PATH=/v1 \
   LLM_API_KEY="$YOUR_API_KEY" OC_CONFIG=/opt/opencode.anthropic.json \
   scripts/10-team-demo.sh
   ```

A `socat` TLS terminator fronts the proxy, because credential injection needs an `https` rule.
The Gateway injects the real key on the hop to Headroom, and Headroom forwards it upstream.
**Headroom therefore sees your real key.**
Compress earlier turns with `kubectl set env deploy/headroom HEADROOM_MODE=token`.
The default `cache` mode freezes them.

## Engram

Engram is a persistent memory server that the agent reaches over MCP.

1. Place an `engram` binary at `image/engram`.
2. Rebuild the image.
3. Run as usual. The config starts `engram mcp`.

Memory lives in `~/.engram`, which is under `/workspace/home` and survives suspend and resume.
To test recall, set both `PROMPT` and `PROMPT2`.
The second prompt starts a new session in the same task.

## Graphify

Graphify builds a code knowledge graph locally, with no LLM and no network.
Build the graph before the image build.

1. Fetch the repository and build the graph:

   ```bash
   cd image
   git clone --depth 1 <repo-url> sample-repo && rm -rf sample-repo/.git
   pip install graphifyy
   graphify update sample-repo
   mkdir graph && mv sample-repo/graphify-out graph/
   rm -rf graph/graphify-out/cache graph/graphify-out/graph.html
   ```

2. Rebuild the image.
   `image/Dockerfile` copies `sample-repo` to `/opt/sample-repo` and `graph` to `/opt/graph`.
3. Run as usual.

The "Code navigation" section of `image/AGENTS.md` tells the agent to run `graphify explain` and `graphify path`
against `/opt/graph/graphify-out/graph.json` before it greps.
To use another repository, change the paths in that section and in `image/Dockerfile`.
