"""TLS reverse proxy in front of a plain-HTTP Ollama server on the host.
The egress gateway only speaks HTTPS to upstreams, so this adds TLS and streams responses through."""
import http.client, os, ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UP_HOST, _, UP_PORT = os.environ["UPSTREAM"].partition(":")
UP_PORT = int(UP_PORT or 11434)
SKIP = {"host", "connection", "transfer-encoding", "content-length"}


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _proxy(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else None
        hdrs = {k: v for k, v in self.headers.items() if k.lower() not in SKIP}
        conn = http.client.HTTPConnection(UP_HOST, UP_PORT, timeout=1800)
        conn.request(self.command, self.path, body, hdrs)
        r = conn.getresponse()
        self.send_response(r.status)
        for k, v in r.getheaders():
            if k.lower() not in SKIP:
                self.send_header(k, v)
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        while chunk := r.read1(8192):
            self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.flush()
        self.wfile.write(b"0\r\n\r\n")
        print(f"{self.command} {self.path} -> {r.status}", flush=True)

    do_GET = do_POST = do_PUT = do_DELETE = _proxy


ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain("/tls/tls.crt", "/tls/tls.key")
srv = ThreadingHTTPServer(("0.0.0.0", 8443), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
