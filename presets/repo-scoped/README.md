# Repo-scoped Claude Code preset (maintainer's local variant)

`claude-code-hooks.settings.json` in this folder is the repo-scoped Claude Code
preset developed and used locally on 2026-10-08 (recovered from
`sweet-no-sleep-presets-local-backup`). It is **not installed by
`Scripts/install-presets.sh`** and the shipped default stays
`presets/claude-code-hooks.settings.json`.

## What is different

| | Shipped default (`presets/claude-code-hooks.settings.json`) | This variant |
| --- | --- | --- |
| Hook command | inline `open -g "sweetnosleep://…"`, shell form | `"${CLAUDE_PROJECT_DIR}/presets/claude-code-hook.sh" <action>` with `timeout: 30` |
| Session id | `claude-${PPID}` | stdin `session_id`, then `$CLAUDE_CODE_SESSION_ID`, then `claude-code-$$` |
| Tool activity | no tool hooks | `PreToolUse` (`Bash\|Task\|Agent`) and `PostToolUse` send `heartbeat` |
| API failure | `Notification(agent_failed\|agent_error) → failed` | `StopFailure → failed` |
| Portability | works from any project or `~/.claude/settings.json` | only works while Claude Code runs inside this checkout |

The variant keeps the lease warm during long tool runs, which the shipped
default only does on `UserPromptSubmit`. The price is the path dependency: the
hook command resolves `${CLAUDE_PROJECT_DIR}/presets/claude-code-hook.sh`, so
`presets/` has to be present in the project Claude Code is running in.

## Install by hand

```bash
mkdir -p .claude
cp presets/repo-scoped/claude-code-hooks.settings.json .claude/settings.json
chmod +x presets/claude-code-hook.sh
```

Check the dispatcher with a stubbed hook payload (it reads the event JSON on
stdin):

```bash
echo '{"session_id":"demo-1"}' | ./presets/claude-code-hook.sh start
echo '{"session_id":"demo-1"}' | ./presets/claude-code-hook.sh waiting
echo '{"session_id":"demo-1"}' | ./presets/claude-code-hook.sh done
```

`jq` is optional: without it the dispatcher falls back to
`$CLAUDE_CODE_SESSION_ID`.

## Status

Kept as a documented alternative so nothing is lost. Promote it to the shipped
default (and teach `Scripts/install-presets.sh` to copy `claude-code-hook.sh`
next to the merged settings) if the tool-activity heartbeats turn out to matter
more than the portability of the inline preset.
