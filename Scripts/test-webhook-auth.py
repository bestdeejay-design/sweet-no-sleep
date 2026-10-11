#!/usr/bin/env python3
"""Unit tests for webhook auth + lifecycle contract (B-05)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from webhook_http_policy import (  # noqa: E402
    WebhookLifecycle,
    action_for,
    authorize,
    parse_session,
    sanitize_reason,
)

TOKEN = "a" * 32


def check(cond: bool, label: str) -> None:
    if not cond:
        raise SystemExit(f"FAIL {label}")
    print(f"ok {label}")


def main() -> int:
    check(action_for("/agent/start") == "start", "path start")
    check(action_for("/agent/heartbeat?x=1") == "heartbeat", "path heartbeat strips query")
    check(action_for("/agent/nope") is None, "unknown path")

    check(authorize({"host": "127.0.0.1:18290", "authorization": f"Bearer {TOKEN}"}, TOKEN) is None, "auth ok")
    check(authorize({"host": "example.com", "authorization": f"Bearer {TOKEN}"}, TOKEN) == 403, "bad host")
    check(
        authorize(
            {"host": "127.0.0.1:18290", "origin": "http://evil", "authorization": f"Bearer {TOKEN}"},
            TOKEN,
        )
        == 403,
        "bad origin",
    )
    check(authorize({"host": "127.0.0.1:18290", "authorization": "Bearer wrong"}, TOKEN) == 401, "bad token")

    status, session, _ = parse_session(b'{"session":"abc"}')
    check(status == 200 and session == "abc", "session json")
    status, _, _ = parse_session(b"")
    check(status == 400, "empty body")
    status, _, _ = parse_session(b'{"session":""}')
    check(status == 400, "empty session")

    life = WebhookLifecycle(TOKEN)
    life.start(port_free=False)
    check(life.error is not None and not life.running, "port occupied at launch")
    life.start(port_free=True)
    check(life.running, "start when free")
    check(life.accept("start", "s1", TOKEN), "deliver while running")
    life.stop()
    check(not life.accept("heartbeat", "s1", TOKEN), "stop drops further events")
    life.regenerate("b" * 32)
    check(not life.accept("start", "s2", TOKEN), "old token rejected after regen")
    check(life.accept("start", "s2", "b" * 32), "new token accepted")
    life.stop()
    life.start()
    life.stop()
    life.start()
    check(life.running, "rapid toggle ends running")

    # Sanitization tests (B-26)
    long_reason = "a" * 500
    check(sanitize_reason(long_reason) == "a" * 200, "500-char reason capped at 200")
    check(sanitize_reason("   \n\t  ") is None, "whitespace-only reason absent")
    check(sanitize_reason("") is None, "empty reason absent")
    check(sanitize_reason(None) is None, "nil reason absent")
    check(sanitize_reason("Approve deploy?") == "Approve deploy?", "normal reason unchanged")
    check(sanitize_reason("Approve\ndeploy?\r\n") == "Approve deploy?", "control chars flattened and trimmed")

    print("Webhook auth/lifecycle tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
