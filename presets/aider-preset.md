# Aider + Sweet No Sleep

Aider has no post-edit or post-commit hooks. Verified against the upstream
`aider/args.py` and `aider/main.py`:

| Candidate | Reality in Aider |
| --- | --- |
| `--post-edit-command` | Does not exist |
| `--post-commit-command` | Does not exist |
| `--format-cmd` | Does not exist |
| `--cwd` | Does not exist; Aider works in the current directory |
| `--alias` | Model alias, format `alias:model-name` (registered in `MODEL_ALIASES`) |
| `aliases:` in `.aider.conf.yml` | Not a config key |
| `--lint-cmd`, `--auto-lint` | Exist |
| `--test-cmd`, `--auto-test` | Exist |
| `--auto-commits`, `--dirty-commits` | Exist |
| `--watch-files` | Exists (watch mode for AI coding comments) |
| `!` shell escape in chat | Exists: runs a shell command, adds output to the chat |

So the lease is driven from outside the editor process instead of from an
editor event.

## Files

- `.aider.conf.yml` — config keys that really exist in this Aider version.
- `aider-agent-wrapper.sh` — starts Aider inside `Scripts/agent-session.sh`.

## Wrapper

```bash
SESSION_ID=aider-1 ./presets/aider-agent-wrapper.sh --message "add a doc comment"
```

`agent-session.sh` sends `start`, then `heartbeat` every
`SWEET_NOSLEEP_HEARTBEAT_SECONDS` (60 s by default, allowed range 10–120), then
`done` or `failed` with Aider's exit status. Signals:

```text
sweetnosleep://agent/start?session=aider-1
sweetnosleep://agent/heartbeat?session=aider-1
sweetnosleep://agent/done?session=aider-1
sweetnosleep://agent/failed?session=aider-1
```

## Manual events from the chat

Aider has no command-alias feature, so use the `!` shell escape. Keep one
session id for the whole session:

```text
!Scripts/agent-event.sh start aider-1
!Scripts/agent-event.sh heartbeat aider-1
!Scripts/agent-event.sh waiting aider-1
!Scripts/agent-event.sh done aider-1
!Scripts/agent-event.sh failed aider-1
```

`waiting` is the state to send when Aider stops and expects an answer from you;
the lease then stops expiring until you send `heartbeat`, `done` or `failed`.
