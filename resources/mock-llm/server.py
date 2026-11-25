"""Minimal OpenAI-compatible mock LLM over TLS. Echoes the Authorization header it received so the
PoC can prove what credential the egress gateway injected."""
import json, ssl, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self._send(200, json.dumps({"object": "list", "data": [{"id": "mock-model", "object": "model"}]}).encode())
        else:
            self._send(200, b'{"ok":true}')

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        req = json.loads(self.rfile.read(n) or b"{}")
        auth = self.headers.get("Authorization", "<none>")
        print(f"POST {self.path} auth={auth!r} stream={req.get('stream')}", flush=True)
        text = f"mock-llm received Authorization: {auth}"
        base = {"id": "mock-1", "created": int(time.time()), "model": req.get("model", "mock-model")}
        usage = {"prompt_tokens": 1, "completion_tokens": 8, "total_tokens": 9}
        if req.get("stream"):
            chunks = [
                {**base, "object": "chat.completion.chunk", "choices": [{"index": 0, "delta": {"role": "assistant", "content": text}}]},
                {**base, "object": "chat.completion.chunk", "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}], "usage": usage},
            ]
            body = "".join(f"data: {json.dumps(c)}\n\n" for c in chunks) + "data: [DONE]\n\n"
            self._send(200, body.encode(), "text/event-stream")
        else:
            self._send(200, json.dumps({**base, "object": "chat.completion", "usage": usage,
                "choices": [{"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": "stop"}]}).encode())


ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain("/tls/tls.crt", "/tls/tls.key")
srv = ThreadingHTTPServer(("0.0.0.0", 8443), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
