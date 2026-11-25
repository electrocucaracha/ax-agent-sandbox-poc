# One Dockerfile for every agent image. The default target is the full agent image
# (OpenCode, rtk, Engram, Graphify and their configs).
ARG BASE_IMAGE=docker.io/library/node:22-slim
FROM ${BASE_IMAGE} AS base
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git curl openssh-client python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*
# Durable state goes under /workspace; the egress gateway's CA must be trusted by the runtime.
ENV HOME=/workspace/home \
    NODE_EXTRA_CA_CERTS=/run/ate/egress-trust-bundle/trust-bundle.pem \
    SSL_CERT_FILE=/run/ate/egress-trust-bundle/trust-bundle.pem
WORKDIR /workspace

FROM base AS agent
RUN npm i -g opencode-ai
RUN pip install --no-cache-dir --break-system-packages graphifyy pytest pytest-randomly pytest-xdist coverage mutmut
COPY rtk engram /usr/local/bin/
COPY opencode*.json AGENTS.md make-demo-repo.sh /opt/
RUN /opt/make-demo-repo.sh
COPY sample-repo /opt/sample-repo
COPY graph /opt/graph
ENV OPENCODE_DISABLE_AUTOUPDATE=true \
    OPENCODE_CONFIG=/opt/opencode.json
