# Agent presets

Ready-to-copy configuration presets that report agent activity to Sweet No
Sleep through `Scripts/agent-event.sh` (`sweetnosleep://agent/<action>?session=<id>`).

| Preset | File | Use |
| --- | --- | --- |
| Claude Code hooks (shipped default) | `claude-code-hooks.settings.json` (same content as `claude-code.settings.json`) | `.claude/settings.json` in the project, or `~/.claude/settings.json` — self-contained, no repo dependency |
| Claude Code hooks (repo-scoped variant) | `repo-scoped/claude-code-hooks.settings.json` + `claude-code-hook.sh` | Same target, but only when Claude Code runs **inside this repository**; richer event coverage |
| Aider | `.aider.conf.yml`, `aider-agent-wrapper.sh`, `aider-preset.md` | Launch Aider inside a lease |
| VS Code / Cursor | `tasks.json` | `.vscode/tasks.json` |

`Scripts/install-presets.sh` installs the shipped default only; the
`repo-scoped/` variant is installed by hand (see below).

## Install

Claude Code — merge `presets/claude-code-hooks.settings.json` into
`.claude/settings.json` (merge the `hooks` object; Claude Code merges hook
entries across settings levels rather than replacing them). The shipped preset
uses shell-form commands only, so no helper script has to be copied:

```bash
./Scripts/install-presets.sh --claude-project .   # merges the hooks for you
# or by hand:
mkdir -p .claude && cp presets/claude-code-hooks.settings.json .claude/settings.json
```

The repo-scoped variant additionally needs its dispatcher, because its hook
commands call `${CLAUDE_PROJECT_DIR}/presets/claude-code-hook.sh`:

```bash
mkdir -p .claude && cp presets/repo-scoped/claude-code-hooks.settings.json .claude/settings.json
chmod +x presets/claude-code-hook.sh
```

Aider — copy the config and run through the wrapper:

```bash
cp presets/.aider.conf.yml .aider.conf.yml
SESSION_ID=aider-1 ./presets/aider-agent-wrapper.sh --message "add a doc comment"
```

VS Code / Cursor — copy to `.vscode/tasks.json`:

```bash
mkdir -p .vscode && cp presets/tasks.json .vscode/tasks.json
```

## Claude Code hooks

### Events used, and why

Shipped default (`claude-code-hooks.settings.json`, self-contained inline
`open` commands; the session id is `claude-${PPID}`, derived from the shell that
Claude Code uses for its hooks):

| Event | Action sent | Why |
| --- | --- | --- |
| `SessionStart` | `start` | Lease begins when a session starts or resumes |
| `UserPromptSubmit` | `heartbeat` | The turn began, the agent is active |
| `Notification` (`agent_needs_input`, `permission_prompt`) | `waiting` | **The agent is waiting for you** |
| `Notification` (`agent_completed`) | `done` | The agent finished its turn |
| `Notification` (`agent_failed`, `agent_error`) | `failed` | The turn ended on an error |
| `Stop` | `done` | Turn finished normally |
| `SessionEnd` | `done` | Safety net; `done` on an already-closed lease is a no-op |

Repo-scoped variant (`repo-scoped/claude-code-hooks.settings.json` +
`claude-code-hook.sh`; the dispatcher prefers the real session id from the hook
payload on stdin, falls back to `$CLAUDE_CODE_SESSION_ID`, then to
`claude-code-$$`):

| Event | Action sent | Why |
| --- | --- | --- |
| `SessionStart` | `start` | Lease begins when a session starts or resumes |
| `UserPromptSubmit` | `heartbeat` | The turn began, the agent is active |
| `PreToolUse` (matcher `Bash\|Task\|Agent`) | `heartbeat` | Agent is running commands or delegating |
| `PostToolUse` | `heartbeat` | Agent produced a result |
| `Notification` (`permission_prompt`, `agent_needs_input`, `elicitation_dialog`, `elicitation_url_dialog`) | `waiting` | **The agent is waiting for you** |
| `Stop` | `done` | Turn finished normally |
| `StopFailure` | `failed` | Turn ended on an API error |
| `SessionEnd` | `done` | Safety net; `done` on an already-closed lease is a no-op |

The variant keeps the lease warm during long tool runs through the
`PreToolUse`/`PostToolUse` heartbeats, and it reports API failures as `failed`.
Its cost is the dependency: the hook commands resolve
`${CLAUDE_PROJECT_DIR}/presets/claude-code-hook.sh`, so it only works while
Claude Code runs in a checkout that has this `presets/` folder.

`Stop` and `SubagentStop` are separate events. `SubagentStop` matches on agent
type and also fires for Claude Code's own internal agents, so it is left out of
both presets; the subagent's tool calls keep the main lease alive through
`PostToolUse`. Add a `SubagentStop` group only if you need per-subagent leases.

`AskUserQuestion` is a tool, not a hook event. To signal on it, add it to a
tool-event matcher and send `waiting`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PROJECT_DIR}/presets/claude-code-hook.sh\" waiting",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

Full list of real events in Claude Code: `SessionStart`, `Setup`,
`UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`,
`PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`,
`Notification`, `MessageDisplay`, `SubagentStart`, `SubagentStop`,
`TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`,
`InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `DirectoryAdded`,
`FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`,
`PreModelSwitch`, `PostModelSwitch`, `Elicitation`, `ElicitationResult`,
`SessionEnd`.

### Configuration fields

- `hooks.<Event>` — array of matcher groups. Events without matcher support
  (including `Stop`, `UserPromptSubmit`, `SessionEnd`) ignore a `matcher` field
  if you add one.
- `matcher` — for tool events it filters the tool name (`Bash|Write|Edit`,
  `mcp__.*__write.*`); for `Notification` it filters the notification type.
  A value made only of letters, digits, `_`, `-`, spaces, `,` and `|` is an
  exact-match list; anything else is an unanchored JavaScript regex.
- `type: "command"` — the handler runs a shell command. `command`, `args`,
  `async`, `asyncRewake`, `shell` are accepted; `if` filters on tool events
  only.
- `timeout` — seconds. Defaults: 600 for command hooks, lowered to 30 on
  `UserPromptSubmit`. `SessionEnd` hooks share a 1.5 s budget, so the preset sets
  5 s there.
- **Shell form vs exec form.** The preset uses shell form (no `args`): the
  command string goes to `sh -c`, so `$CLAUDE_CODE_SESSION_ID` expands from the
  environment. With `args` set there is no shell — `$…` other than the path
  placeholders would be passed through verbatim and break the session id.

### Path placeholders and environment

Available to hook commands and exported into the hook process:

- `${CLAUDE_PROJECT_DIR}` — project root where the session started. Stays on
  the main checkout when Claude enters a worktree; the JSON `cwd` field follows
  Claude instead.
- `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}` — plugin install dir and
  persistent data dir (plugin hooks only).
- `$CLAUDE_CODE_SESSION_ID` — current session id, also available as the stdin
  `session_id` field; updated on `/clear`. The helper prefers the stdin value
  and falls back to this variable.
- `$CLAUDE_CODE_REMOTE` — `"true"` in remote web environments.
- `$CLAUDE_CODE_BRIDGE_SESSION_ID` — Remote Control session id when connected.
- `$CLAUDE_EFFORT` — effort level in effect (`low`…`max`), when the model
  supports it. There is no `$CLAUDE_MODEL`.
- `$CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` — set to `1` to scrub extra variables from
  the hook environment.
- `$CLAUDE_CODE_DEBUG_LOG_LEVEL` — e.g. `verbose`, for hook debug logs.
- `$CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` — SessionEnd hook budget.
- `$CLAUDE_ENV_FILE` — script run before each Bash command; also populated by
  `SessionStart`, `Setup`, `CwdChanged` and `FileChanged` hooks.

Hook payload fields on stdin: `session_id`, `prompt_id`, `transcript_path`,
`cwd`, `scratchpad_dir`, `permission_mode`, `hook_event_name`, plus
`tool_name`/`tool_input` on tool events, `agent_id`/`agent_type` and
`last_assistant_message` on `Stop`/`SubagentStop`, and `notification_type`,
`message`, `title` on `Notification`.

Exit codes: `0` means success (stdout JSON is parsed only when it starts with
`{` and ends with `}`), `2` blocks the action. The helper always exits `0` so a
bridge hiccup can never interrupt the agent.

## Aider

Aider exposes no post-edit or post-commit hooks; verified flags are in
[`aider-preset.md`](aider-preset.md). The wrapper runs Aider inside
`Scripts/agent-session.sh`, so the lease covers the whole session and Aider's
exit status decides `done` versus `failed`.

## VS Code / Cursor

`tasks.json` ships two kinds of task:

- **Discrete events** — `Sweet No Sleep: Agent Start / Heartbeat / Waiting /
  Done / Failed`. Each one calls `Scripts/agent-event.sh <action>
  "${input:agentSessionId}"`, so a task's terminal can drive the pet state by
  hand or from a wrapper. `presentation: { reveal: "silent", close: true }`
  keeps them out of the way; `problemMatcher: []` stops the editor from
  scanning their output.
- **Held builds** — `Build (with Sweet No Sleep hold)` and `Test (with Sweet No
  Sleep hold)` run `swift build` / `swift test` through
  `Scripts/agent-session.sh "${input:agentSessionId}" -- …`, so one lease covers
  the whole build or test run. `group: "build"` / `"test"` binds them to **Run
  Build Task** / **Run Test Task**.

The session id comes from the `agentSessionId` input (`promptString`, default
`vscode-task-1`), so one editor window maps onto one lease; override it per
window to keep several editors apart. `tasks.json` runs the repository's
`Scripts/` through `${workspaceFolder}` — adjust those paths if you copied the
scripts elsewhere, and swap `swift build` for your own build command when
reusing the template in another project.

Cursor is a VS Code fork and reads the same `.vscode/tasks.json`; the Cursor
docs do not define a separate tasks format.

## Verify

```bash
bash Scripts/test-agent-hooks.sh     # mocked URL events, includes waiting
python3 Scripts/validate-localization.py
```

Manual check with a stubbed `open`:

```bash
echo '{"session_id":"demo-1"}' | ./presets/claude-code-hook.sh start
echo '{"session_id":"demo-1"}' | ./presets/claude-code-hook.sh waiting
echo '{"session_id":"demo-1"}' | ./presets/claude-code-hook.sh done
```

Each call runs `open -g "sweetnosleep://agent/<action>?session=demo-1"`, which
only does something when the app is installed and **Settings → Agent bridge** is
enabled.

## Safety

The bridge is unauthenticated local IPC: any local process that can open the URL
scheme can send events. Enable it only for hooks you trust. Agent events can
release a sleep assertion but never start one.
