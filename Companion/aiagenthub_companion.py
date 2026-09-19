#!/usr/bin/env python3
"""
AI Agent Hub Companion
======================

A small, auditable daemon that lets the AI Agent Hub iOS app act on *this* computer
(macOS, Windows or Linux) — only inside directories you allow, and only with commands
you approve.

Security model
--------------
* Pairing: the daemon prints a 6-digit code. The phone POSTs it once to /v1/pair and
  receives a random 32-byte pre-shared key, which it stores in the iOS Keychain.
* Auth: every later request must carry `Authorization: Bearer <key>`.
* Filesystem: reads/writes are confined to --root directories (repeatable flag).
* Shell: disabled unless --allow-shell. Any command not on the allow-list prompts for
  interactive confirmation in this terminal.
* Bind: 127.0.0.1 by default; use --host 0.0.0.0 to expose it on your LAN.

Usage
-----
    python3 aiagenthub_companion.py --root ~/Projects --allow-shell --host 0.0.0.0

No third-party dependencies — standard library only.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import secrets
import shlex
import socket
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VERSION = "1.0.0"

STATE = {
    "pairing_code": f"{secrets.randbelow(1000000):06d}",
    "key": None,
    "roots": [],
    "allow_shell": False,
    "auto_allow": set(),
    "assume_yes": False,
}


def log(msg: str) -> None:
    print(f"[companion] {msg}", flush=True)


def within_roots(path: Path) -> bool:
    try:
        resolved = path.expanduser().resolve()
    except OSError:
        return False
    for root in STATE["roots"]:
        try:
            resolved.relative_to(root)
            return True
        except ValueError:
            continue
    return False


def confirm(prompt: str) -> bool:
    if STATE["assume_yes"]:
        return True
    log(f"APPROVAL REQUIRED: {prompt}")
    try:
        answer = input("Allow? [y/N] ").strip().lower()
    except EOFError:
        return False
    return answer in ("y", "yes")


class Handler(BaseHTTPRequestHandler):
    server_version = f"AIAgentHubCompanion/{VERSION}"

    # ---------- plumbing ----------

    def log_message(self, fmt, *args):  # quieter default logging
        log(f"{self.address_string()} {fmt % args}")

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return {}

    def _authorized(self) -> bool:
        key = STATE["key"]
        if not key:
            return False
        header = self.headers.get("Authorization", "")
        return header.startswith("Bearer ") and secrets.compare_digest(header[7:], key)

    # ---------- routes ----------

    def do_GET(self):  # noqa: N802
        if self.path.rstrip("/") == "/v1/hello":
            if not self._authorized():
                return self._json(401, {"error": "unauthorized"})
            return self._json(200, {
                "hostname": socket.gethostname(),
                "os": {"Darwin": "macOS"}.get(platform.system(), platform.system()),
                "osVersion": platform.release(),
                "arch": platform.machine(),
                "companionVersion": VERSION,
                "allowedRoots": [str(r) for r in STATE["roots"]],
                "shellEnabled": STATE["allow_shell"],
            })
        return self._json(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        route = self.path.rstrip("/")
        body = self._body()

        if route == "/v1/pair":
            if body.get("code") != STATE["pairing_code"]:
                log("Pairing rejected: wrong code.")
                return self._json(403, {"error": "bad pairing code"})
            STATE["key"] = secrets.token_hex(32)
            log(f"Paired with {body.get('device', 'device')}. Key issued.")
            return self._json(200, {"key": STATE["key"]})

        if not self._authorized():
            return self._json(401, {"error": "unauthorized"})

        if route == "/v1/fs/list":
            path = Path(body.get("path", "")).expanduser()
            if not within_roots(path):
                return self._json(403, {"error": f"{path} is outside the allowed roots"})
            if not path.is_dir():
                return self._json(404, {"error": "not a directory"})
            entries = []
            for item in sorted(path.iterdir()):
                entries.append(f"{item.name}/" if item.is_dir() else f"{item.name} ({item.stat().st_size} B)")
            return self._json(200, {"entries": entries})

        if route == "/v1/fs/read":
            path = Path(body.get("path", "")).expanduser()
            if not within_roots(path):
                return self._json(403, {"error": f"{path} is outside the allowed roots"})
            if not path.is_file():
                return self._json(404, {"error": "not a file"})
            try:
                return self._json(200, {"content": path.read_text(errors="replace")[:400_000]})
            except OSError as exc:
                return self._json(500, {"error": str(exc)})

        if route == "/v1/fs/write":
            path = Path(body.get("path", "")).expanduser()
            if not within_roots(path):
                return self._json(403, {"error": f"{path} is outside the allowed roots"})
            if not confirm(f"write {path} ({len(body.get('content', ''))} bytes)"):
                return self._json(403, {"error": "denied by the computer's owner"})
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body.get("content", ""))
            log(f"Wrote {path}")
            return self._json(200, {"ok": True})

        if route == "/v1/exec":
            if not STATE["allow_shell"]:
                return self._json(403, {"error": "shell execution is disabled on this host"})
            command = body.get("command", "")
            cwd = body.get("cwd") or str(STATE["roots"][0])
            if not within_roots(Path(cwd)):
                return self._json(403, {"error": f"{cwd} is outside the allowed roots"})
            head = shlex.split(command)[0] if command.strip() else ""
            if head not in STATE["auto_allow"] and not confirm(f"run `{command}` in {cwd}"):
                return self._json(403, {"error": "denied by the computer's owner"})
            try:
                proc = subprocess.run(command, shell=True, cwd=cwd, capture_output=True,
                                      text=True, timeout=300)
                return self._json(200, {
                    "exitCode": proc.returncode,
                    "stdout": proc.stdout[-40_000:],
                    "stderr": proc.stderr[-20_000:],
                })
            except subprocess.TimeoutExpired:
                return self._json(200, {"exitCode": 124, "stdout": "", "stderr": "timeout after 300s"})

        return self._json(404, {"error": "not found"})


def local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="AI Agent Hub Companion")
    parser.add_argument("--root", action="append", default=[], help="allowed directory (repeatable)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--allow-shell", action="store_true")
    parser.add_argument("--auto-allow", action="append", default=[],
                        help="command name runnable without a prompt, e.g. git")
    parser.add_argument("--yes", action="store_true", help="skip interactive prompts (use with care)")
    args = parser.parse_args()

    roots = [Path(r).expanduser().resolve() for r in (args.root or [Path.cwd()])]
    for r in roots:
        if not r.exists():
            log(f"Root {r} does not exist")
            return 1
    STATE["roots"] = roots
    STATE["allow_shell"] = args.allow_shell
    STATE["auto_allow"] = set(args.auto_allow)
    STATE["assume_yes"] = args.yes

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    log(f"AI Agent Hub Companion {VERSION} on {platform.system()} {platform.release()}")
    log(f"Listening on http://{args.host}:{args.port}  (LAN address: http://{local_ip()}:{args.port})")
    log(f"Allowed roots: {', '.join(str(r) for r in roots)}")
    log(f"Shell: {'ENABLED' if args.allow_shell else 'disabled'}")
    log("")
    log(f"  PAIRING CODE: {STATE['pairing_code']}")
    log("  Enter it in AI Agent Hub → Settings → Computer companion")
    log("")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutting down.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
