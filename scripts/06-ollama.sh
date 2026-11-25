#!/usr/bin/env bash
# Check an external Ollama server (for example https://ollama.example.com) that the agents will use.
# Nothing is deployed and no model is loaded: this only lists the models the server has.
# scripts/10-team-demo.sh reads the same OLLAMA_URL and sends the agents' requests through the egress gateway.
# Env: OLLAMA_URL (required, HTTPS), OLLAMA_MODEL (default qwen2.5-coder:7b; warns when not listed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=./scripts/_utils.sh
source "$HERE/scripts/_utils.sh"
OLLAMA_URL=${OLLAMA_URL:-}
MODEL=${OLLAMA_MODEL:-qwen2.5-coder:7b}

[[ "$OLLAMA_URL" =~ ^https://[^[:space:]/@?#]+(/[^[:space:]?#@]*)?$ ]] ||
  { error "OLLAMA_URL must be an HTTPS base URL without credentials, query or fragment, e.g. https://ollama.example.com"; exit 1; }
OLLAMA_URL=${OLLAMA_URL%/}

tags=$(curl -fsS --max-time 15 "$OLLAMA_URL/api/tags") || { error "Ollama is not answering at $OLLAMA_URL/api/tags"; exit 1; }
if printf %s "$tags" | python3 -c 'import json, sys; sys.exit(0 if any(m.get("name") == sys.argv[1] for m in json.load(sys.stdin)["models"]) else 1)' "$MODEL"; then
  echo "ollama reachable: $OLLAMA_URL (model $MODEL listed)"
else
  echo "WARN: ollama reachable at $OLLAMA_URL but model $MODEL is not listed; pull it on that server before running the demo"
fi
echo "run: OLLAMA_URL=$OLLAMA_URL scripts/10-team-demo.sh"
