# Run the team demo with an external Ollama server

Connect the team-demo agents to an Ollama server you manage by setting `OLLAMA_URL`.
This project does not deploy Ollama or an Ollama proxy.
You can check the endpoint without loading a model before starting the demo.

## Before you begin

- Complete the [project setup](../../README.md#quickstart) through the git-server step.
  Do not start the team demo yet.
  Running `scripts/main.sh` without phase arguments also starts the demo.
- Run the commands below from the repository root.
  The endpoint check needs Bash, `curl` and Python 3; it does not need a cluster.
- Use an HTTPS hostname that resolves and is reachable from both your workstation and the cluster's egress gateway.
  Prefer the standard HTTPS port, `443`.
- Before running the full demo, make a tool-capable model available on the external server.
  The endpoint check does not require an installed model.

> [!IMPORTANT]
> The egress gateway only connects to HTTPS upstreams.
> `http://localhost:11434` is not a usable upstream URL.
> `localhost` inside the cluster does not refer to your workstation.

## 1. Provide an HTTPS endpoint

If your external service already provides HTTPS, use its base URL and continue to step 2.
Otherwise, configure a TLS reverse proxy **outside this project**, on the Ollama host or your existing ingress.
Forward both `/api/tags` and `/v1/*`, preserving their paths and streaming responses.

For example, on an external host with Caddy installed and Ollama listening on `127.0.0.1:11434`,
add this site to your Caddy configuration.
Replace the hostname and certificate paths with your own:

```caddyfile
ollama.example.com {
    tls /etc/caddy/certs/ollama.crt /etc/caddy/certs/ollama.key
    reverse_proxy 127.0.0.1:11434 {
        flush_interval -1
    }
}
```

Use a certificate valid for the hostname, including its intermediate certificate chain.
Validate and reload the configuration using your Caddy service's administrative account:

```bash
caddy validate --config /etc/caddy/Caddyfile
caddy reload --config /etc/caddy/Caddyfile
```

Configure DNS and firewall rules so your workstation and the egress gateway can reach that hostname on port 443.
Keep Ollama's HTTP listener private.
Ollama does not enforce the demo's placeholder API key, so do not expose this unauthenticated endpoint to the public internet.
Restrict access to trusted clients using your network or reverse-proxy controls.
The example assumes the proxy and Ollama run on the same host, not in separate containers.

## 2. Check connectivity without inference

Set the server's base URL, **without** `/api/tags` or `/v1`.
Replace the example hostname:

```bash
export OLLAMA_URL=https://ollama.example.com
scripts/06-ollama.sh
```

The script calls only `GET ${OLLAMA_URL}/api/tags` and checks the returned model names.
It does not print a full model list, pull a model, load one into memory, or call a generation endpoint.
When the default model is installed, expect:

```text
ollama reachable: https://ollama.example.com (model qwen2.5-coder:7b listed)
run: OLLAMA_URL=https://ollama.example.com scripts/10-team-demo.sh
```

An empty model list produces a warning and still exits successfully.
A missing model is not a connectivity failure.
An invalid URL or failed HTTP request exits nonzero.

For a private certificate authority (CA), supply its PEM bundle to the local probe:

```bash
CURL_CA_BUNDLE=/absolute/path/to/ollama-ca-bundle.pem scripts/06-ollama.sh
```

Separately, [add that CA to the egress gateway's trust bundle](trust-private-ca.md) before running agents.
`CURL_CA_BUNDLE` affects the workstation probe, not the gateway.
Preserve the existing mock and git-server CAs when updating the gateway bundle.
Do not disable certificate verification.

**Stop here if you only need a check without model inference.**
This verifies access from your workstation, not the cluster's network path.
The remaining steps prepare and run model-backed agents.

## 3. Match the agent configuration to the server's model

The default model is `qwen2.5-coder:7b`.
If it is missing, have the external server's operator make it available before running the demo.
The probe never installs it.

To select another model:

1. Edit [image/opencode.ollama.json](../../image/opencode.ollama.json).
   Set `model` to `ollama/<model-tag>` and replace both the key and `name` under `provider.ollama.models` with that exact tag.
2. Rebuild the local agent image, assuming the [local build inputs](../reference/scripts-and-configuration.md#03-build-push-imagesh-variables) are available:

   ```bash
   IMAGE_SOURCE=local scripts/main.sh image
   ```

   If you use a prebuilt image, publish and select an updated compatible image containing the changed configuration instead.
3. Check that the selected model is listed, for example:

   ```bash
   OLLAMA_MODEL=qwen2.5-coder:14b scripts/06-ollama.sh
   ```

`OLLAMA_MODEL` changes only the probe's expected model.
It does not change the agents' configuration.
Skip the edit and rebuild if you use the default model and your image already contains `/opt/opencode.ollama.json`.

## 4. Run the model-backed demo

Check your shell and ignored `.env.opencode` file for settings left over from another provider.
For the Ollama defaults, remove `LITELLM_PROXY_API_BASE`, `LITELLM_PROXY_API_KEY`, `LITELLM_PROXY_MODEL`,
`OC_CONFIG` and `LLM_MODEL_ID` overrides unless you intend to use them.
The demo sources `.env.opencode`; changing only your shell may not remove saved overrides.

With `OLLAMA_URL` still exported from step 2, run:

```bash
EPIC_TIMEOUT=3600 scripts/10-team-demo.sh
```

**This command makes inference requests and consumes model resources.**
It also recreates the demo repositories `alpha/app` and `beta/app`, removing their previous branches and pull requests.
Collect any results you need before rerunning it.

When `OLLAMA_URL` is selected, the script derives `LLM_HOST` and `LLM_PATH` from it,
allows the upstream host through each tenant's egress gateway, and sets the agents' base URL to `${OLLAMA_URL}/v1`.
The default OpenCode configuration is `/opt/opencode.ollama.json`.
The gateway injects the key; agents retain only a placeholder.

An explicit `LITELLM_PROXY_API_BASE` takes precedence over `OLLAMA_URL` and bypasses the Ollama-specific defaults.
An explicit `OC_CONFIG` overrides the default config.
The key defaults to `ollama`, with `LLM_API_KEY` overriding that default and `LITELLM_PROXY_API_KEY` taking precedence over both.
See the [configuration reference](../reference/scripts-and-configuration.md#10-team-demosh-variables) for all settings.

Watch the script's wave output and check the resulting pull requests as described in [Run the team demo](run-team-demo.md).
Task completion alone does not mean the generated feature passes its quality gates.

After collecting results, clean up even if the demo failed:

```bash
scripts/10-team-demo.sh down
```

This removes demo tasks, workspaces and team gateways, and scales the worker pool back to one.
It does not stop or change your external Ollama service or TLS reverse proxy.

## Adjust server capacity

- Allow more time for slow models with `EPIC_TIMEOUT`; mutation has a separate `MUTATION_TIMEOUT`.
- Set `OLLAMA_NUM_PARALLEL` on the external server according to its available memory.
  The demo runs multiple agents concurrently; insufficient server capacity can queue or delay requests.
- Set an appropriate `OLLAMA_CONTEXT_LENGTH` on the server, for example `32768`, accounting for its memory cost.
- Use a model with reliable tool calling.
  A successful endpoint check does not establish that the model can complete the epic.

## If it fails

| Symptom                                  | Likely cause                                                                             |
| ---------------------------------------- | ---------------------------------------------------------------------------------------- |
| `OLLAMA_URL must be an HTTPS base URL`   | The URL is plain HTTP, has credentials, a query or a fragment. Use an HTTPS reverse proxy. |
| `Ollama is not answering`                | Check DNS, firewall access, `/api/tags` forwarding and workstation CA trust. For a private CA, set `CURL_CA_BUNDLE` for the probe. |
| `WARN: ... model ... is not listed`      | Ask the server operator to install the model, or match `OLLAMA_MODEL` to the exact installed tag. Do not treat this as model readiness. |
| Probe succeeds, agents cannot connect    | Check reachability from the gateway, gateway CA trust, and streaming `/v1/*` forwarding. A workstation probe does not test these. |
| Agents use the previous provider         | Remove conflicting `LITELLM_PROXY_API_BASE` and `OC_CONFIG` settings from both your shell and `.env.opencode`. |
| `model not found`                         | Match the model tag in the image's Ollama config to the external server's model list; rebuild or replace the image after editing it. |
| Agents loop or never call tools          | The model lacks tool support, or the context is too small. Use a larger model.           |

## Verification scope

The probe was checked against a temporary HTTPS stub serving `/api/tags`, including a missing-model warning and HTTP-URL rejection.
That check loaded no model.
It did not verify a real Ollama inference request, the external reverse-proxy example, or a full Ollama-backed epic.
The separately recorded real-provider team-demo results do not establish Ollama compatibility.

See also [Troubleshoot](troubleshoot.md) and [Run the team demo](run-team-demo.md).
