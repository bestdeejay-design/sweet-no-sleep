#!/usr/bin/env bash
# Launch Aider inside a Sweet No Sleep agent lease.
# Aider has no post-edit or post-commit hooks, so the lease is managed around
# the process instead: Scripts/agent-session.sh sends start, heartbeats every
# 60 s and a final done or failed event.
# Aider has no --cwd flag, so the repository root is set by changing directory.
# Usage: SESSION_ID=aider-1 ./presets/aider-agent-wrapper.sh --message "..."
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
AGENT_SESSION="${REPO_ROOT}/Scripts/agent-session.sh"

SESSION_ID="${SESSION_ID:-aider-$$}"

if ! command -v aider >/dev/null 2>&1; then
  echo "aider is not installed or not on PATH." >&2
  exit 127
fi

cd "$REPO_ROOT" || exit 1
exec "${AGENT_SESSION}" "$SESSION_ID" -- aider "$@"
