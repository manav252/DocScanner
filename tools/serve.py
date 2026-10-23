#!/usr/bin/env python3
"""Serve the showcase website at / and the Flutter web app at /app/ (stdlib only).

    python3 tools/serve.py [--port 8080] [--host 127.0.0.1]

Every response is sent with `Cache-Control: no-cache`, so a rebuilt app or
updated test results show up on the next reload.
Use --host 0.0.0.0 to open it from a phone on the same Wi-Fi (camera access on
a phone browser needs https; see the README).
"""
import argparse
import functools
import http.server
import mimetypes
import os
import socketserver
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "website"
APP = ROOT / "app" / "build" / "web"

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("text/javascript", ".mjs")
mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("application/json", ".json")


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path: str) -> str:
        clean = path.split("?", 1)[0].split("#", 1)[0]
        if clean == "/app" or clean.startswith("/app/"):
            rel = clean[len("/app"):].lstrip("/")
            base = APP
        else:
            rel = clean.lstrip("/")
            base = SITE
        target = (base / rel).resolve()
        # Never serve files outside the two folders.
        if base.resolve() not in (target, *target.parents):
            return str(base / "__missing__")
        return str(target)

    def do_GET(self):
        if self.path.split("?", 1)[0] == "/app":
            self.send_response(301)
            self.send_header("Location", "/app/")
            self.end_headers()
            return
        super().do_GET()

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):  # quieter: errors only
        if args and str(args[1]).startswith(("4", "5")):
            super().log_message(fmt, *args)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", 8080)))
    ap.add_argument("--host", default="127.0.0.1")
    a = ap.parse_args()
    if not (APP / "index.html").exists():
        print(f"warning: {APP} has no build yet; run ./start.sh (it builds the app) or flutter build web")
    with Server((a.host, a.port), functools.partial(Handler)) as httpd:
        print(f"Website:  http://localhost:{a.port}/")
        print(f"Web app:  http://localhost:{a.port}/app/")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
