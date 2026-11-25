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
LLM_HOST=llm.example.com \
LLM_PATH=/gateway/v1 \
LLM_API_KEY="$YOUR_API_KEY" \
OC_CONFIG=/opt/opencode.anthropic.json \
scripts/10-team-demo.sh
```

Use `/opt/opencode.local.json` for `OC_CONFIG` if you made a local copy.

`LLM_PATH` is the base path before `/messages` or `/chat/completions`.
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
`resources/team/gateway.yaml` injects the key into both.
Remove the rule you do not need.

## If the call fails

See [Troubleshoot](troubleshoot.md).
If the endpoint uses a private CA, see [Trust a private CA](trust-private-ca.md).
