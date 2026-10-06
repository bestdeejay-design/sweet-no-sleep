#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
export HOOK_LOG="$TEMP_DIR/open.log"
mkdir -p "$TEMP_DIR/bin"

cat > "$TEMP_DIR/bin/open" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOOK_LOG"
STUB
chmod +x "$TEMP_DIR/bin/open"
export PATH="$TEMP_DIR/bin:$PATH"
: > "$HOOK_LOG"

"$ROOT_DIR/Scripts/agent-event.sh" start smoke-1
"$ROOT_DIR/Scripts/agent-event.sh" heartbeat smoke-1
"$ROOT_DIR/Scripts/agent-event.sh" done smoke-1

if "$ROOT_DIR/Scripts/agent-event.sh" start 'bad id' >/dev/null 2>&1; then
  echo "Invalid session ID unexpectedly passed validation." >&2
  exit 1
fi
if "$ROOT_DIR/Scripts/agent-event.sh" unsupported smoke-1 >/dev/null 2>&1; then
  echo "Invalid event unexpectedly passed validation." >&2
  exit 1
fi

SWEET_NOSLEEP_HEARTBEAT_SECONDS=10 \
  "$ROOT_DIR/Scripts/agent-session.sh" smoke-success -- bash -c 'exit 0'

set +e
SWEET_NOSLEEP_HEARTBEAT_SECONDS=10 \
  "$ROOT_DIR/Scripts/agent-session.sh" smoke-failure -- bash -c 'exit 7'
command_status=$?
set -e
if [[ "$command_status" -ne 7 ]]; then
  echo "agent-session.sh returned $command_status; expected the wrapped command's status 7." >&2
  exit 1
fi

if ! grep -q 'sweetnosleep://agent/start?session=smoke-1' "$HOOK_LOG" \
  || ! grep -q 'sweetnosleep://agent/heartbeat?session=smoke-1' "$HOOK_LOG" \
  || ! grep -q 'sweetnosleep://agent/done?session=smoke-1' "$HOOK_LOG" \
  || ! grep -q 'sweetnosleep://agent/start?session=smoke-success' "$HOOK_LOG" \
  || ! grep -q 'sweetnosleep://agent/done?session=smoke-success' "$HOOK_LOG" \
  || ! grep -q 'sweetnosleep://agent/start?session=smoke-failure' "$HOOK_LOG" \
  || ! grep -q 'sweetnosleep://agent/failed?session=smoke-failure' "$HOOK_LOG"; then
  echo "Agent hook events did not match expected start/heartbeat/terminal sequence:" >&2
  cat "$HOOK_LOG" >&2
  exit 1
fi

printf 'Agent hook smoke tests passed (%s mocked URL events).\n' "$(wc -l < "$HOOK_LOG" | tr -d ' ')"
