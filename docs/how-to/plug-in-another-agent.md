# Plug in another agent

Run a different coding agent CLI in the sandbox.

## Requirements

The agent must:

- run headless from a single command,
- read its API key and base URL from environment variables or a config file,
- not install packages at runtime, because the sandbox has no registry access.

## Steps

1. Add a stage to `image/Dockerfile` that starts `FROM base AS <agent>` and installs the agent.
   Install everything at build time.
2. Build and push the image:

   ```bash
   IMAGE_NAME=<agent>-task \
   ENV_VAR=AGENT_IMAGE ENV_FILE=.env.<agent> \
   scripts/03-build-push-image.sh
   ```

3. Copy `resources/task/` to a new directory, for example `resources/my-agent/`.
   Change the container command and the placeholder variable names.
   Keep the Gateway section: it holds the allowlist and `replaceHeaders` rules.
4. Make the agent trust the gateway CA.
   For Node agents, set `NODE_EXTRA_CA_CERTS=/run/ate/egress-trust-bundle/trust-bundle.pem`.
5. Copy `scripts/10-team-demo.sh`, point it at your template and image variable,
   and run it.

## Check

Inside the task, run `ax ssh <task> -- env`.
The key variable must read `placeholder`.
The LLM must still answer.
