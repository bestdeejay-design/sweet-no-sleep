"""Documented webhook HTTP policy (keep in sync with AgentWebhookServer.swift).

Used by Scripts/test-webhook-auth.py so Linux CI can lock the contract
without the macOS Network.framework listener.
"""
from __future__ import annotations

EXPECTED_HOST = "127.0.0.1:18290"
EXPECTED_ORIGIN = "http://127.0.0.1:18290"
MAX_BODY = 4 * 1024
ACTIONS = {
    "/agent/start": "start",
    "/agent/heartbeat": "heartbeat",
    "/agent/waiting": "waiting",
    "/agent/done": "done",
    "/agent/failed": "failed",
}


def constant_time_equal(lhs: str, rhs: str) -> bool:
    left = lhs.encode("utf-8")
    right = rhs.encode("utf-8")
    if len(left) != len(right):
        return False
    diff = 0
    for a, b in zip(left, right):
        diff |= a ^ b
    return diff == 0


def action_for(raw_path: str) -> str | None:
    path = raw_path.split("?", 1)[0]
    return ACTIONS.get(path)


def authorize(headers: dict[str, str], token: str) -> int | None:
    """Return an HTTP error status, or None if the request may continue."""
    host = (headers.get("host") or "").strip()
    if host != EXPECTED_HOST:
        return 403
    origin = (headers.get("origin") or "").strip()
    if origin and origin not in (EXPECTED_ORIGIN, "null"):
        return 403
    auth = headers.get("authorization") or ""
    if not constant_time_equal(auth, f"Bearer {token}"):
        return 401
    return None


def parse_session(body: bytes) -> tuple[int, str | None, str | None]:
    import json

    if not body:
        return 400, None, None
    if len(body) > MAX_BODY:
        return 413, None, None
    try:
        decoded = json.loads(body.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        return 400, None, None
    if not isinstance(decoded, dict):
        return 400, None, None
    session = decoded.get("session")
    if not isinstance(session, str) or not session or len(session) > 120:
        return 400, None, None
    reason = decoded.get("reason")
    reason_text = reason if isinstance(reason, str) else None
    return 200, session, reason_text


def sanitize_reason(reason: str | None) -> str | None:
    """Keep reason text safe: one line, no control chars, capped at 200, None if empty."""
    if not reason:
        return None
    import re
    flattened = re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", reason).strip()
    if not flattened:
        return None
    return flattened[:200]


class WebhookLifecycle:
    """Minimal model of toggle / bind / token-regen / in-flight drop."""

    def __init__(self, token: str) -> None:
        self.token = token
        self.running = False
        self.port_owner = False
        self.in_flight: list[str] = []
        self.delivered: list[tuple[str, str]] = []
        self.error: str | None = None

    def start(self, port_free: bool = True) -> None:
        if not port_free:
            self.running = False
            self.port_owner = False
            self.error = "Port 18290 is already in use"
            return
        self.running = True
        self.port_owner = True
        self.error = None

    def stop(self) -> None:
        self.running = False
        self.port_owner = False
        self.in_flight.clear()
        self.error = None

    def regenerate(self, new_token: str, port_free: bool = True) -> None:
        self.stop()
        self.token = new_token
        self.start(port_free=port_free)

    def accept(self, action: str, session: str, token: str) -> bool:
        if not self.running:
            return False
        if not constant_time_equal(f"Bearer {token}", f"Bearer {self.token}"):
            return False
        key = f"{action}:{session}"
        self.in_flight.append(key)
        if not self.running:
            return False
        self.in_flight.remove(key)
        self.delivered.append((action, session))
        return True
