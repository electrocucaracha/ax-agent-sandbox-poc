# Use a real LLM endpoint

Point the sandboxed agent at your own LLM endpoint instead of the mock.

## Before you begin

- The cluster is running ([tutorial](../tutorials/first-task.md), steps 1–4).
- You have an API key and the endpoint host name.
- The worker pods can resolve the host name.

## 1. Find the API format and path

Test the endpoint from your host with `curl` first.
Some gateways serve a model in only one format.

| Format             | Path                   | Provider package                                      |
| ------------------ | ---------------------- | ----------------------------------------------------- |
| OpenAI chat        | `/v1/chat/completions` | OpenAI-compatible (default `image/opencode.json`)     |
| Anthropic messages | `/v1/messages`         | `@ai-sdk/anthropic` (`image/opencode.anthropic.json`) |

## 2. Set the model and headers

Edit the config for your format, for example `image/opencode.anthropic.json`:

- Set the model name under `provider.gateway.models`.
- Add static headers, such as `anthropic-version` or tenant headers, under `options.headers`.

To keep headers out of version control, copy the file to `image/opencode.local.json`
and edit the copy.
Git ignores `opencode.local*.json`.

## 3. Rebuild the image

```bash
scripts/03-build-push-image.sh
```

## 4. Run the task

```bash
LITELLM_PROXY_API_BASE=https://llm.example.com/gateway \
LITELLM_PROXY_API_KEY="$YOUR_API_KEY" \
LITELLM_PROXY_MODEL=anthropic/claude-sonnet-4-6 \
LITELLM_EXTRA_HEADERS_JSON='{"WM_LLM_GW.USER_TYPE":"developer","WM_LLM_GW.USER_NAME":"your-user-id"}' \
OC_CONFIG=/opt/opencode.anthropic.json \
LLM_AUTH_MODE=x-api-key \
scripts/10-team-demo.sh
```

Use `/opt/opencode.local.json` for `OC_CONFIG` if you made a local copy.

`LLM_PATH` is the base path before `/messages` or `/chat/completions`.
If your gateway host includes a path prefix, you can include it in `LLM_HOST`
(for example, `llm.example.com/gateway`) and keep the API base path in
`LLM_PATH` (for example, `/v1`); the demo combines them for the request URL
while using only the hostname in the egress allowlist.
`LLM_MODEL_ID` replaces the selected model's provider-facing name in the config.
When `LITELLM_PROXY_API_BASE` is set, it overrides `LLM_HOST` and `LLM_PATH`;
its HTTPS host is added to the Gateway allowlist and the path is normalized for the API.
Use `LLM_AUTH_MODE=x-api-key` for Anthropic API-key authentication; it removes the extra bearer header.
`LLM_EXTRA_HEADERS_JSON` optionally merges string-valued headers into that provider's config.
Do not put credentials in this setting; use `LLM_API_KEY` for the injected API key.
The demo also accepts `CHANGELOG_LITELLM_HEADERS_JSON` as an alias for `LLM_EXTRA_HEADERS_JSON`.
It also accepts `LITELLM_EXTRA_HEADERS_JSON`; `LITELLM_PROXY_API_KEY` is preferred over `LLM_API_KEY`.
For an Anthropic `LITELLM_PROXY_MODEL` such as `anthropic/claude-sonnet-4-6`, the model portion is used as the provider-facing model name unless `LLM_MODEL_ID` is set.
The epic and the agent definitions (role instructions) are Markdown files in `agents/` (see [Run the team demo](run-team-demo.md)).
Edit the file and re-run the demo; no image rebuild is needed.
With the mock endpoint the replies are canned, so the prompts only change the output with a real model.

## 5. Read the result

The demo prints each agent's output.
To read it again while the tasks are `Working`:

```bash
ax -a alpha ssh developer -- cat /workspace/out.log
```

`ax ssh` works only while the task is `Working`.

## Header injection

The Anthropic SDK sends the key in `x-api-key`.
OpenAI-compatible clients send `Authorization: Bearer`.
Set `LLM_AUTH_MODE=x-api-key` when the endpoint accepts only `x-api-key`; the Gateway then injects only that header.
The default `both` also injects `Authorization` through the `resources/team-both/` overlay.

## If the call fails

See [Troubleshoot](troubleshoot.md).
If the endpoint uses a private CA, see [Trust a private CA](trust-private-ca.md).
