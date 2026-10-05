#!/usr/bin/env python3
"""Serve the Web export in build/web on the local network, and collect
playtest telemetry.

    python3 tools/serve_web.py [port] [--log-dir DIR]

Open http://<this machine's LAN IP>:<port>/ on a phone on the same network.
Add ?scenario=bench_4000 (or skirmish, battle_2000, battle_4000, bench_2000)
to jump straight into a scenario, and &speed=0..3 for 0.5x/1x/2x/4x.
The export is single-threaded, so no cross-origin isolation headers are
needed (that is what makes it work on iOS Safari).

Telemetry: the game POSTs JSON to /telemetry, either one record object or
{"records": [...]}. Each record is appended as one line to
<log-dir>/YYYY-MM-DD.jsonl (default log dir: playtest_logs/ at the repo root,
gitignored), stamped with "recv" (server UTC time) and "ip". GET /telemetry
returns a small JSON status. Read the logs with tools/playtest_report.py.
Standard library only.
"""
import argparse
import datetime
import functools
import http.server
import json
import os
import socket
import sys
import threading

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ROOT = os.path.join(REPO, "build", "web")
DEFAULT_LOG_DIR = os.path.join(REPO, "playtest_logs")
MAX_BODY = 512 * 1024      # bytes per POST
MAX_RECORDS = 2000         # records per POST
MAX_RECORD_BYTES = 64 * 1024

_lock = threading.Lock()
_stats = {"records": 0, "posts": 0, "rejected": 0, "started": None}


def _log_path(log_dir):
    day = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    return os.path.join(log_dir, day + ".jsonl")


class Handler(http.server.SimpleHTTPRequestHandler):
    log_dir = DEFAULT_LOG_DIR
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "application/javascript",
        ".pck": "application/octet-stream",
    }

    def end_headers(self):
        # Avoid stale builds on phones while iterating.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _path_only(self):
        return self.path.split("?", 1)[0].rstrip("/")

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self._path_only() == "/telemetry":
            with _lock:
                status = dict(_stats)
            status.update({"ok": True, "log_file": _log_path(self.log_dir)})
            self._json(200, status)
            return
        super().do_GET()

    def do_POST(self):
        try:
            if self._path_only() != "/telemetry":
                self._json(404, {"ok": False, "error": "not found"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = -1
            if length < 0 or length > MAX_BODY:
                with _lock:
                    _stats["rejected"] += 1
                self._json(413, {"ok": False, "error": "body too large or bad length"})
                self.close_connection = True
                return
            raw = self.rfile.read(length) if length else b""
            try:
                data = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                with _lock:
                    _stats["rejected"] += 1
                self._json(400, {"ok": False, "error": "invalid json"})
                return
            if isinstance(data, dict) and isinstance(data.get("records"), list):
                records = data["records"][:MAX_RECORDS]
            elif isinstance(data, dict):
                records = [data]
            else:
                with _lock:
                    _stats["rejected"] += 1
                self._json(400, {"ok": False, "error": "expected an object"})
                return
            recv = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds")
            ip = self.client_address[0] if self.client_address else ""
            # Behind a reverse proxy the socket peer is the proxy; record the
            # original client as well (not trusted, for device grouping only).
            fwd = self.headers.get("X-Forwarded-For", "")
            if fwd:
                ip = fwd.split(",")[0].strip()[:64] + " via " + ip
            lines = []
            for r in records:
                if not isinstance(r, dict):
                    continue
                rec = {"recv": recv, "ip": ip}
                rec.update(r)
                rec["recv"], rec["ip"] = recv, ip  # server values always win
                line = json.dumps(rec, separators=(",", ":"), ensure_ascii=False)
                if len(line) <= MAX_RECORD_BYTES:
                    lines.append(line)
            if lines:
                with _lock:
                    os.makedirs(self.log_dir, exist_ok=True)
                    with open(_log_path(self.log_dir), "a", encoding="utf-8") as f:
                        f.write("\n".join(lines) + "\n")
                    _stats["records"] += len(lines)
                    _stats["posts"] += 1
            self._json(200, {"ok": True, "stored": len(lines)})
        except Exception as e:  # never let a bad request kill the server
            try:
                self._json(500, {"ok": False, "error": type(e).__name__})
            except Exception:
                pass

    def log_message(self, fmt, *args):
        # Keep the console readable: skip the periodic telemetry posts.
        if self.command == "POST" and self._path_only() == "/telemetry":
            return
        super().log_message(fmt, *args)


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("port", nargs="?", type=int, default=8060)
    ap.add_argument("--cert", help="TLS certificate (PEM); enables HTTPS")
    ap.add_argument("--key", help="TLS private key (PEM)")
    ap.add_argument("--log-dir", default=DEFAULT_LOG_DIR,
                    help="where telemetry JSONL files go (default: playtest_logs/)")
    args = ap.parse_args()
    if not os.path.exists(os.path.join(ROOT, "index.html")):
        sys.exit("No build/web/index.html: export first with tools/export_web.sh")
    log_dir = os.path.abspath(args.log_dir)
    handler_cls = type("BoundHandler", (Handler,), {"log_dir": log_dir})
    handler = functools.partial(handler_cls, directory=ROOT)
    _stats["started"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    with http.server.ThreadingHTTPServer(("0.0.0.0", args.port), handler) as httpd:
        scheme = "http"
        if args.cert:
            # Godot's web build needs a secure context, so anything other than
            # localhost has to be served over HTTPS (a self-signed cert is fine).
            import ssl
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ctx.load_cert_chain(args.cert, args.key)
            httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
            scheme = "https"
        print(f"Serving {ROOT}")
        print(f"  local:     {scheme}://127.0.0.1:{args.port}/")
        print(f"  network:   {scheme}://{lan_ip()}:{args.port}/")
        print(f"  telemetry: {log_dir}/<date>.jsonl  (GET /telemetry for status)")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
