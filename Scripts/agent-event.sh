#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <start|heartbeat|done|failed> <session-id>" >&2
  exit 64
fi

ACTION="$1"
SESSION_ID="$2"
case "$ACTION" in
  start|heartbeat|done|failed) ;;
  *) echo "Unsupported event: $ACTION" >&2; exit 64 ;;
esac

if [[ ! "$SESSION_ID" =~ ^[A-Za-z0-9._-]{1,120}$ ]]; then
  echo "Session ID must be 1-120 letters, numbers, dots, underscores or hyphens." >&2
  exit 64
fi

# 'open -g' sends the local custom URL event without bringing the menu app forward.
open -g "sweetnosleep://agent/$ACTION?session=$SESSION_ID"
