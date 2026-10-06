#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EVENT_SCRIPT="$SCRIPT_DIR/agent-event.sh"

if [[ $# -lt 3 || "$2" != "--" ]]; then
  echo "Usage: $0 <session-id> -- <agent-command> [args...]" >&2
  echo "Example: $0 local-agent-1 -- ./run-my-agent.sh" >&2
  exit 64
fi

SESSION_ID="$1"
shift 2
HEARTBEAT_SECONDS="${SWEET_NOSLEEP_HEARTBEAT_SECONDS:-60}"
if [[ ! "$HEARTBEAT_SECONDS" =~ ^[0-9]+$ ]] || (( HEARTBEAT_SECONDS < 10 || HEARTBEAT_SECONDS > 120 )); then
  echo "SWEET_NOSLEEP_HEARTBEAT_SECONDS must be an integer from 10 to 120." >&2
  exit 64
fi

send_event() {
  "$EVENT_SCRIPT" "$1" "$SESSION_ID"
}

if ! send_event start; then
  echo "Could not send the start event. Check that Sweet No Sleep is installed and its local bridge is enabled." >&2
  exit 1
fi

heartbeat_loop() {
  local sleep_pid=""
  trap 'if [[ -n "${sleep_pid:-}" ]]; then kill "$sleep_pid" 2>/dev/null || true; fi; exit 0' TERM INT
  while :; do
    sleep "$HEARTBEAT_SECONDS" &
    sleep_pid=$!
    wait "$sleep_pid"
    local sleep_status=$?
    sleep_pid=""
    (( sleep_status == 0 )) || return 0
    "$EVENT_SCRIPT" heartbeat "$SESSION_ID" >/dev/null 2>&1 || true
  done
}

heartbeat_loop &
HEARTBEAT_PID=$!

finish_session() {
  local command_status="$1"
  trap - INT TERM
  kill "$HEARTBEAT_PID" 2>/dev/null || true
  wait "$HEARTBEAT_PID" 2>/dev/null || true

  if (( command_status == 0 )); then
    send_event done || echo "Warning: could not send the done event." >&2
  else
    send_event failed || echo "Warning: could not send the failed event." >&2
  fi
  exit "$command_status"
}

trap 'finish_session 130' INT
trap 'finish_session 143' TERM

"$@"
COMMAND_STATUS=$?
finish_session "$COMMAND_STATUS"
