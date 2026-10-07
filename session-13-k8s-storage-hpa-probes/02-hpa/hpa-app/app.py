# CPU-heavy web app, equivalent to the Kubernetes HPA walkthrough's php-apache image
# (registry.k8s.io/hpa-example is amd64-only). Each request burns CPU, then returns "OK!".
import math
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        x = 0.0001
        for i in range(1_000_000):
            x += math.sqrt(x)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK!")

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("", 80), Handler).serve_forever()
