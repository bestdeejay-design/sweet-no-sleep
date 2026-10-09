#!/usr/bin/env python3
"""Smoke-test mcp-server/server.py: start, list tools, call hold, assert delivery (B-06)."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "mcp-server" / "server.py"


def rpc(proc: subprocess.Popen, payload: dict) -> dict:
    proc.stdin.write(json.dumps(payload) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        raise SystemExit("MCP server produced no response")
    return json.loads(line)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        log = Path(tmp) / "open.log"
        bin_dir = Path(tmp) / "bin"
        bin_dir.mkdir()
        stub = bin_dir / "open"
        stub.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"$HOOK_LOG\"\n", encoding="utf-8")
        stub.chmod(0o755)
        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
        env["HOOK_LOG"] = str(log)
        env["SWEET_NOSLEEP_WEBHOOK_TOKEN"] = ""
        proc = subprocess.Popen(
            [sys.executable, str(SERVER)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        try:
            listed = rpc(proc, {"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
            names = [t["name"] for t in listed["result"]["tools"]]
            if "sweetnosleep_hold" not in names:
                raise SystemExit(f"missing hold tool: {names}")
            called = rpc(
                proc,
                {
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "tools/call",
                    "params": {
                        "name": "sweetnosleep_hold",
                        "arguments": {"session_id": "mcp-smoke", "reason": "ci"},
                    },
                },
            )
            text = called["result"]["content"][0]["text"]
            payload = json.loads(text)
            if payload.get("ok") != "true":
                raise SystemExit(f"hold not delivered: {payload}")
        finally:
            proc.stdin.close()
            proc.kill()
            proc.wait(timeout=5)
        logged = log.read_text(encoding="utf-8") if log.is_file() else ""
        if "sweetnosleep://agent/start?session=mcp-smoke" not in logged:
            raise SystemExit(f"open stub did not record start: {logged!r}")
    print("MCP server smoke test passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
