#!/usr/bin/env bash
# Interactive installer for Sweet No Sleep agent presets (F5).
# Copies Claude Code hooks and Cursor/VS Code tasks into place.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRESETS_DIR="$ROOT_DIR/presets"

CLAUDE_USER_SETTINGS="$HOME/.claude/settings.json"
VSCODE_TASKS_HINT="<workspace>/.vscode/tasks.json"

usage() {
  cat <<'HELP'
Usage: install-presets.sh [--claude-user] [--claude-project [DIR]] [--tasks [DIR]] [--all] [--list]

  --claude-user        Install Claude Code hooks into ~/.claude/settings.json (merged).
  --claude-project DIR Install Claude Code hooks into DIR/.claude/settings.json (merged, default DIR=. ).
  --tasks DIR          Copy tasks.json hint into DIR/.vscode/tasks.json (default DIR=. ).
  --all                Install user-level Claude hooks and print tasks.json guidance.
  --list               Show available preset files.
  (no args)            Interactive menu.
HELP
}

list_presets() {
  echo "Available presets in presets/:"
  for file in "$PRESETS_DIR"/*.json; do
    echo "  - $(basename "$file")"
  done
}

merge_claude_hooks() {
  local dest="$1"
  local preset="$PRESETS_DIR/claude-code-hooks.settings.json"
  mkdir -p "$(dirname "$dest")"
  python3 - "$preset" "$dest" <<'PY'
import json, sys
preset_path, dest_path = sys.argv[1], sys.argv[2]
preset = json.load(open(preset_path))
try:
    existing = json.load(open(dest_path))
except (FileNotFoundError, json.JSONDecodeError):
    existing = {}
hooks = existing.get("hooks", {})
for event, entries in preset.get("hooks", {}).items():
    current = hooks.get(event, [])
    for entry in entries:
        if entry not in current:
            current.append(entry)
    hooks[event] = current
existing["hooks"] = hooks
with open(dest_path, "w") as handle:
    json.dump(existing, handle, indent=2)
    handle.write("\n")
print(f"Merged Claude hooks into {dest_path}")
PY
}

install_tasks() {
  local dest_dir="$1"
  local dest="$dest_dir/.vscode/tasks.json"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]]; then
    echo "Found existing $dest."
    echo "Merge the Sweet No Sleep tasks from presets/tasks.json by hand; refusing to overwrite."
    return 1
  fi
  cp "$PRESETS_DIR/tasks.json" "$dest"
  echo "Installed Cursor/VS Code tasks into $dest"
}

prompt_yes_no() {
  local prompt="$1"
  local answer
  read -r -p "$prompt [y/N] " answer || true
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

interactive() {
  echo "Sweet No Sleep preset installer"
  echo ""
  list_presets
  echo ""
  if prompt_yes_no "Install Claude Code hooks into $CLAUDE_USER_SETTINGS?"; then
    merge_claude_hooks "$CLAUDE_USER_SETTINGS"
  else
    echo "Skipped user-level Claude hooks."
  fi
  echo ""
  if prompt_yes_no "Install Claude Code hooks into ./.claude/settings.json for this project?"; then
    merge_claude_hooks "$PWD/.claude/settings.json"
  else
    echo "Skipped project-level Claude hooks."
  fi
  echo ""
  if prompt_yes_no "Copy tasks.json into ./.vscode/tasks.json for this project?"; then
    install_tasks "$PWD" || true
  else
    echo "Skipped tasks.json. Merge presets/tasks.json into $VSCODE_TASKS_HINT by hand."
  fi
  echo ""
  echo "Done. Enable the bridge in Settings > Power > AI agent connection, then run Scripts/test-agent-hooks.sh."
}

if [[ $# -eq 0 ]]; then
  interactive
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --list) list_presets; exit 0 ;;
    --claude-user) merge_claude_hooks "$CLAUDE_USER_SETTINGS"; shift ;;
    --claude-project)
      shift
      dir="${1:-.}"
      [[ "$dir" == -* ]] && { dir="."; } || shift || true
      merge_claude_hooks "$dir/.claude/settings.json"
      ;;
    --tasks)
      shift
      dir="${1:-.}"
      [[ "$dir" == -* ]] && { dir="."; } || shift || true
      install_tasks "$dir"
      ;;
    --all)
      merge_claude_hooks "$CLAUDE_USER_SETTINGS"
      echo "For Cursor/VS Code, merge presets/tasks.json into $VSCODE_TASKS_HINT by hand."
      shift
      ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
done
