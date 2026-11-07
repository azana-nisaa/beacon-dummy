#!/usr/bin/env python3
"""Beacon Dummy — stdlib-only HTTP canary for DR drills."""

from __future__ import annotations

import json
import os
import platform
import signal
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
STATIC = ROOT / "static"
STARTED_AT = time.time()
REQUESTS = 0
LOCK = threading.Lock()

HOST = os.environ.get("BEACON_HOST", "0.0.0.0")
PORT = int(os.environ.get("BEACON_PORT", "8080"))
ROLE = os.environ.get("BEACON_ROLE", "dummy")
SITE_NAME = os.environ.get("BEACON_SITE_NAME", "Beacon Canary")

MIME = {
    ".css": "text/css; charset=utf-8",
    ".html": "text/html; charset=utf-8",
    ".ico": "image/x-icon",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".txt": "text/plain; charset=utf-8",
    ".png": "image/png",
    ".woff2": "font/woff2",
}


def local_ips() -> list[str]:
    found: list[str] = []

    def add(ip: str) -> None:
        if not ip:
            return
        if ip.startswith("127.") or ip.startswith("169.254.") or ip in (":1", "::1"):
            return
        if ip not in found:
            found.append(ip)

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(0.3)
            sock.connect(("1.1.1.1", 80))
            add(sock.getsockname()[0])
    except OSError:
        pass

    hostname = socket.gethostname()
    try:
        for info in socket.getaddrinfo(hostname, None):
            add(info[4][0])
    except OSError:
        pass

    try:
        add(socket.gethostbyname(hostname))
    except OSError:
        pass

    try:
        out = subprocess.check_output(["hostname", "-I"], text=True, timeout=1)
        for token in out.split():
            add(token)
    except (OSError, subprocess.SubprocessError):
        pass

    return found or ["127.0.0.1"]


def status_payload() -> dict:
    with LOCK:
        requests = REQUESTS
    now = time.time()
    return {
        "ok": True,
        "service": "beacon-dummy",
        "site_name": SITE_NAME,
        "role": ROLE,
        "hostname": socket.gethostname(),
        "ips": local_ips(),
        "now": time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(now)),
        "unix": int(now),
        "uptime_seconds": int(now - STARTED_AT),
        "requests": requests,
        "python": platform.python_version(),
        "platform": platform.platform(),
        "pid": os.getpid(),
        "port": PORT,
    }


class BeaconHandler(BaseHTTPRequestHandler):
    server_version = "BeaconDummy/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.log_date_time_string(), fmt % args))

    def do_HEAD(self) -> None:
        self._dispatch(body=False)

    def do_GET(self) -> None:
        self._dispatch(body=True)

    def _bump(self) -> None:
        global REQUESTS
        with LOCK:
            REQUESTS += 1

    def _dispatch(self, body: bool) -> None:
        self._bump()
        path = urlparse(self.path).path
        if path in ("/health", "/healthz", "/ready"):
            self._send_bytes(
                200,
                b"ok\n",
                "text/plain; charset=utf-8",
                body,
                cache=False,
            )
            return
        if path in ("/api/health", "/api/status", "/status.json"):
            payload = status_payload()
            raw = json.dumps(payload, indent=2).encode("utf-8") + b"\n"
            self._send_bytes(200, raw, "application/json; charset=utf-8", body, cache=False)
            return
        self._serve_static(path, body)

    def _serve_static(self, path: str, body: bool) -> None:
        rel = "index.html" if path in ("", "/") else path.lstrip("/")
        target = (STATIC / rel).resolve()
        try:
            target.relative_to(STATIC.resolve())
        except ValueError:
            self._send_bytes(403, b"forbidden\n", "text/plain; charset=utf-8", body, cache=False)
            return
        if target.is_dir():
            target = target / "index.html"
        if not target.is_file():
            html = (STATIC / "404.html")
            if html.is_file():
                data = html.read_bytes()
                self._send_bytes(404, data, "text/html; charset=utf-8", body, cache=False)
            else:
                self._send_bytes(404, b"not found\n", "text/plain; charset=utf-8", body, cache=False)
            return
        mime = MIME.get(target.suffix.lower(), "application/octet-stream")
        self._send_bytes(200, target.read_bytes(), mime, body, cache=True)

    def _send_bytes(
        self,
        code: int,
        data: bytes,
        content_type: str,
        body: bool,
        cache: bool,
    ) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Beacon", "alive")
        self.send_header("X-Beacon-Role", ROLE)
        if cache:
            self.send_header("Cache-Control", "public, max-age=120")
        else:
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(data)


def main() -> int:
    if not STATIC.exists():
        sys.stderr.write("static/ folder is missing next to server.py\n")
        return 1

    httpd = ThreadingHTTPServer((HOST, PORT), BeaconHandler)

    def shutdown(signum, _frame):
        sys.stderr.write("\nbeacon: shutting down (%s)\n" % signum)
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    banner = [
        "",
        "  Beacon Dummy  ·  DR canary",
        "  --------------------------------",
        "  site     %s" % SITE_NAME,
        "  role     %s" % ROLE,
        "  listen   http://%s:%s" % (HOST, PORT),
        "  health   /health  /api/status",
        "",
    ]
    sys.stderr.write("\n".join(banner) + "\n")
    try:
        httpd.serve_forever(poll_interval=0.5)
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
