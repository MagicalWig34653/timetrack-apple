#!/usr/bin/env python3
"""Adds a fixed delay to every request before forwarding it to a (throwaway) backend, to emulate watch-over-radio latency (A12).

usage: latency-proxy.py <listen-port> <backend-port> <delay-ms> [outage-file]
Ports must be >= 19800 and never 18080. While <outage-file> exists every request answers 503 after the delay, which the
app sees like an unreachable server (used for the offline-queue screenshots). Loopback only, no logging of headers or bodies.
"""
import http.server, os, socketserver, sys, time, urllib.request, urllib.error

listen, backend, delay = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]) / 1000
outage = sys.argv[4] if len(sys.argv) > 4 else None
assert listen >= 19800 and backend >= 19800 and 18080 not in (listen, backend)

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def handle_any(self):
        time.sleep(delay)
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        if outage and os.path.exists(outage):
            self.send_response(503); self.send_header("Content-Length", "0"); self.end_headers(); return
        request = urllib.request.Request(f"http://127.0.0.1:{backend}{self.path}", data=body, method=self.command,
                                         headers={k: v for k, v in self.headers.items() if k.lower() not in ("host", "connection")})
        try:
            response = urllib.request.urlopen(request)
        except urllib.error.HTTPError as error:
            response = error
        data = response.read()
        self.send_response(response.status)
        for name, value in response.headers.items():
            if name.lower() not in ("transfer-encoding", "connection", "content-length"):
                self.send_header(name, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_any
    def log_message(self, *args): pass

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

Server(("127.0.0.1", listen), Handler).serve_forever()
