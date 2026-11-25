FROM docker.io/library/python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends socat ca-certificates && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir "headroom-ai[proxy]"
# TLS terminator in front of the plain-HTTP proxy: Gateway egress rules that inject credentials require https.
CMD ["sh", "-c", "headroom proxy --host 127.0.0.1 --port 8787 --no-http2 & exec socat OPENSSL-LISTEN:8443,reuseaddr,fork,cert=/tls/tls.crt,key=/tls/tls.key,verify=0 TCP:127.0.0.1:8787"]
