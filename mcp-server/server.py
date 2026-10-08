#!/usr/bin/env python3
"""Sweet No Sleep MCP server (stdlib only, JSON-RPC 2.0 over stdio).

Exposes three tools to MCP-compatible agents:
  - sweetnosleep_hold: start or renew an awake hold for a session.
  - sweetnosleep_waiting: mark a session as waiting for user approval.
  - sweetnosleep_release: release a session with success/failed status.

Transport: HTTP POST to the app's loopback webhook
(http://127.0.0.1:18290/agent/<action>) with a bearer token from
SWEET_NOSLEEP_WEBHOOK_TOKEN. On connection refusal (app not running or
webhook disabled), falls back to `open sweetnosleep://agent/...`.

Only the standard library is used. All logs go to stderr so stdout stays
clean JSON-RPC.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

WEBHOOK_BASE = os.environ.get("SWEET_NOSLEEP_WEBHOOK_URL", "http://127.0.0.1:18290")
WEBHOOK_TOKEN = os.environ.get("SWEET_NOSLEEP_WEBHOOK_TOKEN", "")
SERVER_NAME = "sweet-no-sleep"
SERVER_VERSION = "1.0.0"


def log(message: str) -> None:
    print(f"[sweet-no-sleep-mcp] {message}", file=sys.stderr, flush=True)


def post_webhook(action: str, session_id: str, reason: str | None) -> tuple[bool, str]:
    """POST to the loopback webhook. Returns (delivered, detail)."""
    url = f"{WEBHOOK_BASE}/agent/{action}"
    payload: dict[str, str] = {"session": session_id}
    if reason:
        payload["reason"] = reason[:200]
    data = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Content-Length": str(len(data)),
        "Host": "127.0.0.1:18290",
        "Connection": "close",
    }
    if WEBHOOK_TOKEN:
        headers["Authorization"] = f"Bearer {WEBHOOK_TOKEN}"
    request = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            body = response.read().decode("utf-8", "replace")
            return True, f"webhook {response.status}: {body}"
    except urllib.error.HTTPError as exc:
        try:
            detail = exc.read().decode("utf-8", "replace")
        except Exception:
            detail = ""
        return False, f"webhook HTTP {exc.code}: {detail}"
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return False, f"webhook unreachable: {exc}"


def open_url_scheme(action: str, session_id: str, reason: str | None) -> tuple[bool, str]:
    """Fallback delivery via the sweetnosleep:// URL scheme (macOS `open`)."""
    from urllib.parse import quote

    target = f"sweetnosleep://agent/{action}?session={quote(session_id, safe='')}"
    if reason:
        target += f"&reason={quote(reason[:200], safe='')}"
    try:
        completed = subprocess.run(
            ["open", "-g", target],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except FileNotFoundError:
        return False, "fallback `open` command not found"
    except subprocess.TimeoutExpired:
        return False, "fallback `open` timed out"
    if completed.returncode == 0:
        return True, f"url-scheme fallback delivered: {action} {session_id}"
    stderr = (completed.stderr or "").strip()
    return False, f"url-scheme fallback failed ({completed.returncode}): {stderr}"


def deliver(action: str, session_id: str, reason: str | None = None) -> dict[str, str]:
    """Deliver one agent event, preferring the webhook with URL fallback."""
    if not session_id or len(session_id) > 120:
        return {"ok": "false", "detail": "session_id must be 1-120 characters"}
    if not WEBHOOK_TOKEN:
        log(f"no webhook token configured; using url-scheme fallback for {action} {session_id}")
        fallback_ok, fallback_detail = open_url_scheme(action, session_id, reason)
        return {"ok": "true" if fallback_ok else "false", "detail": fallback_detail}
    ok, detail = post_webhook(action, session_id, reason)
    if ok:
        log(f"{action} {session_id} via webhook")
        return {"ok": "true", "detail": detail}
    log(f"webhook failed for {action} {session_id}: {detail}; trying url-scheme fallback")
    # Only fall back on connection-level failures, not on auth/validation errors.
    if "webhook unreachable" not in detail and "Connection refused" not in detail:
        # Still attempt fallback for robustness, but report the webhook error first.
        pass
    fallback_ok, fallback_detail = open_url_scheme(action, session_id, reason)
    log(f"fallback {action} {session_id}: {fallback_detail}")
    return {"ok": "true" if fallback_ok else "false", "detail": f"{detail} | {fallback_detail}"}


TOOLS = [
    {
        "name": "sweetnosleep_hold",
        "description": "Acquire or renew a Sweet No Sleep awake hold for a planned batch of agent work. Call at session start and about once a minute via heartbeat.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string", "description": "Stable session identifier (1-120 chars)."},
                "reason": {"type": "string", "description": "Short human-readable reason for the hold."},
            },
            "required": ["session_id"],
        },
    },
    {
        "name": "sweetnosleep_waiting",
        "description": "Mark a session as waiting for user approval (y/n, diff review, command confirmation). Kiwi shows an attentive pose until heartbeats resume.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string", "description": "Stable session identifier (1-120 chars)."},
                "reason": {"type": "string", "description": "What the agent needs approval for."},
            },
            "required": ["session_id"],
        },
    },
    {
        "name": "sweetnosleep_release",
        "description": "Release the awake hold and report the final outcome of a session.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string", "description": "Stable session identifier (1-120 chars)."},
                "status": {"type": "string", "enum": ["success", "failed"], "description": "Final session outcome."},
                "summary": {"type": "string", "description": "One-line outcome summary."},
            },
            "required": ["session_id", "status"],
        },
    },
]


def handle_tools_call(params: dict) -> dict:
    name = params.get("name", "")
    arguments = params.get("arguments", {}) or {}
    session_id = str(arguments.get("session_id", ""))
    reason = arguments.get("reason")
    reason_text = str(reason) if reason is not None else None
    if name == "sweetnosleep_hold":
        result = deliver("start", session_id, reason_text)
    elif name == "sweetnosleep_waiting":
        result = deliver("waiting", session_id, reason_text)
    elif name == "sweetnosleep_release":
        status = str(arguments.get("status", "success"))
        summary = arguments.get("summary")
        summary_text = str(summary) if summary is not None else None
        action = "done" if status == "success" else "failed"
        result = deliver(action, session_id, summary_text or reason_text)
    else:
        return {
            "content": [{"type": "text", "text": json.dumps({"ok": "false", "detail": f"unknown tool: {name}"})}],
            "isError": True,
        }
    return {
        "content": [{"type": "text", "text": json.dumps(result)}],
        "isError": result.get("ok") != "true",
    }


def handle_request(message: dict) -> dict | None:
    """Handle one JSON-RPC message. Returns a response dict or None for notifications."""
    method = message.get("method", "")
    msg_id = message.get("id")
    params = message.get("params", {}) or {}

    def response(result: dict) -> dict:
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    def error(code: int, text: str) -> dict:
        return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": text}}

    # Notifications (no id) never get a response.
    if msg_id is None:
        log(f"notification: {method}")
        return None

    if method == "initialize":
        return response(
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            }
        )
    if method == "ping":
        return response({})
    if method == "tools/list":
        return response({"tools": TOOLS})
    if method == "tools/call":
        if not isinstance(params, dict):
            return error(-32602, "invalid params")
        return response(handle_tools_call(params))
    if method in ("shutdown", "exit"):
        return response({})
    return error(-32601, f"method not found: {method}")


def main() -> int:
    log(f"{SERVER_NAME} {SERVER_VERSION} starting (stdio, webhook {WEBHOOK_BASE})")
    stdin = sys.stdin
    stdout = sys.stdout
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError as exc:
            log(f"invalid JSON, skipping: {exc}")
            reply = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}}
            stdout.write(json.dumps(reply) + "\n")
            stdout.flush()
            continue
        try:
            reply = handle_request(message)
        except Exception as exc:  # Never let one bad message kill the server.
            log(f"handler error: {exc}")
            reply = {
                "jsonrpc": "2.0",
                "id": message.get("id"),
                "error": {"code": -32603, "message": "internal error"},
            }
        if reply is not None:
            stdout.write(json.dumps(reply) + "\n")
            stdout.flush()
    log("stdin closed, exiting")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
