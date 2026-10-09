#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <start|heartbeat|waiting|done|failed> <session-id> [reason]" >&2
  exit 64
fi

ACTION="$1"
SESSION_ID="$2"
REASON="${3:-}"
case "$ACTION" in
  start|heartbeat|waiting|done|failed) ;;
  *) echo "Unsupported event: $ACTION" >&2; exit 64 ;;
esac

if [[ ! "$SESSION_ID" =~ ^[A-Za-z0-9._-]{1,120}$ ]]; then
  echo "Session ID must be 1-120 letters, numbers, dots, underscores or hyphens." >&2
  exit 64
fi

url_encode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

TARGET="sweetnosleep://agent/$ACTION?session=$SESSION_ID"
if [[ -n "$REASON" ]]; then
  TARGET="$TARGET&reason=$(url_encode "${REASON:0:200}")"
fi

# Route by bundle id so LaunchServices does not wake a stale checkout copy.
# Fall back to the URL scheme if this bundle is not registered yet.
if ! open -g -b com.sweetnosleep.kiwicat "$TARGET" 2>/dev/null; then
  open -g "$TARGET"
fi
