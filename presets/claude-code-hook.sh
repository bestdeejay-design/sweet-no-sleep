#!/usr/bin/env bash
# Claude Code hook dispatcher for the Sweet No Sleep agent bridge.
# Claude Code passes the event payload as JSON on stdin; the session id comes
# from stdin .session_id first and $CLAUDE_CODE_SESSION_ID as a fallback.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
EVENT_SCRIPT="${REPO_ROOT}/Scripts/agent-event.sh"

action="${1:-}"
case "$action" in
  start|heartbeat|waiting|done|failed) ;;
  *)
    echo "Usage: $0 <start|heartbeat|waiting|done|failed>" >&2
    exit 64
    ;;
esac

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
if [[ -z "$session_id" ]]; then
  session_id="${CLAUDE_CODE_SESSION_ID:-}"
fi
if [[ -z "$session_id" ]]; then
  session_id="claude-code-$$"
fi

"$EVENT_SCRIPT" "$action" "$session_id" || true
exit 0
