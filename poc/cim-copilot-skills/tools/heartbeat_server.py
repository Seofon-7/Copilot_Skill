#!/usr/bin/env python3
"""Optional: tiny HTTP receiver for sync heartbeats (standard library only).

Use this instead of (or in addition to) a shared folder when engineers should
not have write access to a network share. It stores each heartbeat as
<REPORT_DIR>/<user>@<host>.json - the same format the shared-folder option
produces - so report-dashboard.ps1 works unchanged.

Run on an internal server:
    python heartbeat_server.py --port 8080 --report-dir D:\\cim-skills-status

Then set in each engineer's config.json:
    "reportUrl": "http://<server>:8080/api/heartbeat"

Intranet use only. There is no authentication: put it behind your usual
reverse proxy / firewall rules if needed.
"""
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_BODY = 64 * 1024
SAFE_RE = re.compile(r"[^A-Za-z0-9._@-]")


def make_handler(report_dir: Path):
    class Handler(BaseHTTPRequestHandler):
        server_version = "cim-skills-heartbeat/1.0"

        def _send(self, code: int, payload: dict) -> None:
            body = json.dumps(payload).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/health":
                self._send(200, {"ok": True})
            elif self.path == "/api/status":
                items = []
                for f in sorted(report_dir.glob("*.json")):
                    try:
                        items.append(json.loads(f.read_text(encoding="utf-8-sig")))
                    except (OSError, ValueError):
                        continue
                self._send(200, {"count": len(items), "items": items})
            else:
                self._send(404, {"error": "not found"})

        def do_POST(self) -> None:  # noqa: N802
            if self.path != "/api/heartbeat":
                self._send(404, {"error": "not found"})
                return
            length = int(self.headers.get("Content-Length") or 0)
            if length <= 0 or length > MAX_BODY:
                self._send(400, {"error": "missing or too large body"})
                return
            try:
                data = json.loads(self.rfile.read(length).decode("utf-8-sig"))
            except (UnicodeDecodeError, ValueError):
                self._send(400, {"error": "invalid JSON"})
                return
            if not isinstance(data, dict) or not data.get("user") or not data.get("host"):
                self._send(400, {"error": "user and host are required"})
                return
            data["receivedAt"] = datetime.now(timezone.utc).isoformat()
            data["clientIp"] = self.client_address[0]
            name = SAFE_RE.sub("_", f"{data['user']}@{data['host']}")
            target = report_dir / f"{name}.json"
            tmp = target.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
            tmp.replace(target)
            self._send(200, {"ok": True})

        def log_message(self, fmt: str, *args) -> None:  # quieter log
            print(f"{self.address_string()} - {fmt % args}")

    return Handler


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--report-dir", default="./reports")
    args = ap.parse_args()
    report_dir = Path(args.report_dir)
    report_dir.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(report_dir))
    print(f"Listening on http://{args.host}:{args.port}  (reports -> {report_dir.resolve()})")
    server.serve_forever()


if __name__ == "__main__":
    main()
