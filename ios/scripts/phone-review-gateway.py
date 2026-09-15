#!/usr/bin/env python3
"""Private LAN gateway for a developer's own phone, without restarting jobs.

Reads an ignored JSON config containing host, port and a random token. The
phone's review-only API base includes that token; other paths are not served.
The upstream remains loopback-only. Stop this process to end phone access.
"""
import argparse
import hmac
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from urllib.parse import urlsplit


def handler(config):
    class Gateway(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass  # Do not log the private URL or user content.

        def forward(self):
            parts = self.path.split("/", 2)
            if len(parts) != 3 or not hmac.compare_digest(parts[1], config["token"]):
                self.send_error(404)
                return
            path = "/" + parts[2]
            route = urlsplit(path).path
            allowed = route.startswith("/api/mobile/") or (
                self.command in ("GET", "HEAD") and
                route.startswith(("/files/", "/runs/", "/api/assets/"))
            )
            if not allowed:
                self.send_error(404)
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                self.send_error(400)
                return
            if size < 0 or size > 25 * 1024 * 1024 or self.headers.get("Transfer-Encoding"):
                self.send_error(413)
                return
            upstream = http.client.HTTPConnection("127.0.0.1", 8001, timeout=120)
            response_started = False
            try:
                headers = {k: v for k, v in self.headers.items()
                           if k.lower() not in ("host", "connection", "transfer-encoding")}
                upstream.request(self.command, path, self.rfile.read(size) if size else None, headers)
                response = upstream.getresponse()
                self.send_response(response.status)
                for key, value in response.getheaders():
                    if key.lower() not in ("connection", "transfer-encoding", "server", "date"):
                        self.send_header(key, value)
                self.send_header("Connection", "close")
                self.end_headers()
                response_started = True
                if self.command != "HEAD":
                    while chunk := response.read(65536):
                        self.wfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass
            except (OSError, http.client.HTTPException):
                if not response_started:
                    data = json.dumps({"detail": "Studio server unavailable. Keep the Mac awake and start the studio server."}).encode()
                    self.send_response(503)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(data)))
                    self.send_header("Retry-After", "5")
                    self.end_headers()
                    if self.command != "HEAD": self.wfile.write(data)
            finally:
                upstream.close()

        do_GET = do_HEAD = do_POST = do_PUT = do_DELETE = forward

    return Gateway


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    args = parser.parse_args()
    with open(args.config) as file:
        config = json.load(file)
    if len(config["token"]) < 32:
        raise ValueError("A random review token of at least 32 characters is required")
    server = ThreadingHTTPServer((config["host"], config["port"]), handler(config))
    print("Private phone review gateway ready", flush=True)
    server.serve_forever()
