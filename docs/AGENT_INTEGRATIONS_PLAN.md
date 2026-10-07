# AI Agent Integrations v2 — Implementation Plan

A decision-complete implementation plan for the five improvement tracks from
[Issue #10](https://github.com/bestdeejay-design/sweet-no-sleep/issues/10)
(spec: `docs/AGENT_INTEGRATIONS.md`) plus one visual-indicator feature requested
by the maintainer. This document is the contract for the arena consultation:
the arena reviews every option, picks the recommended path (or proposes a
better one), and returns a detailed spec for the build.

---

## 0. Visual agent-activity indicator ("muzzle status light")

**Goal.** While at least one agent session is active, the center of Kiwi's
round chest badge shows a colored status light so the user can tell at a glance
that an agent is holding the Mac awake — and when the agent is waiting for
input.

**Source of truth (already in the model).** `SweetNoSleepModel.agentLeases`
(`[String: Date]`) + `activeAgentCount` (`@Published`). A new computed flag
`isAgentActive` (= `!agentLeases.isEmpty`) and `isAgentWaiting` (Feature 1)
drive the light; no new plumbing needed for the data.

**Light states.**

| State   | Visual                                             | Trigger                     |
|---------|----------------------------------------------------|-----------------------------|
| Off     | default kiwi seed pattern in badge center          | no active agent lease       |
| Working | soft pulse, period synced to the 60 s heartbeat    | `!agentLeases.isEmpty`      |
| Waiting | bright pulse + `?`/`!` overhead + raised paw + y/n bubble | `waiting` event (Feature 1) |

**Implementation options.**

- **A (recommended).** Re-purpose the badge core in `drawKiwiBadge`
  (`KiwiPetView.swift:453`): replace the static center seed with a filled
  circle in a configurable indicator color; pulse via `1 + sin(time * f)`
  (pattern already used at line 456). Smallest visual delta, works at the
  45 pt minimum pet size.
- **B (reserve).** Outer halo ring around the badge (leaves badge untouched) —
  less readable at small sizes, so it is not the first choice.
- **C (complement).** Floating indicator above the head (pattern: sparkle at
  `KiwiPetView.swift:307`). Conflicts with the `?`/`!` glyph from Feature 1, so
  it is only a secondary signal — not recommended as the primary light.

**Detection source (configurable in Settings > Agent).**

- (a) **Agent Bridge lease** — event-driven, already implemented (default).
- (b) **Process scan** — `NSWorkspace.runningApplications` matching configured
  names (`claude`, `aider`, `cursor`, `python`, …). Works without leases but is
  noisy; opt-in only.
- (c) **Webhook / MCP events** — becomes the preferred source after
  Features 2–3 land.

**Files.** `KiwiPetView.swift` (badge rendering), `SweetNoSleepModel.swift`
(computed flags), `SettingsView.swift` (color picker + source checkboxes),
`Localizable.xcstrings` (new strings via `Scripts/localize.sh`).

---

## 1. `waiting_for_approval` state

**Goal.** Agents pause mid-workflow awaiting a human decision (`y/n`, diff
review, command confirmation). Kiwi should visibly switch to an attentive,
questioning posture and post a notification, then return to the working state
on the next heartbeat.

**Model changes (`SweetNoSleepModel.swift`).**

- Extend the lease store without breaking existing code:
  `agentSessions: [String: AgentSessionState]` where
  `AgentSessionState { status: working | waiting, expiry: Date }`; keep a
  computed `agentLeases`-like view for the existing paths, or migrate cleanly.
- `handleAgentURL` (`:431`): add `case "waiting"` →
  `setAgentWaiting(sessionID:)`; `heartbeat` for a known session flips
  `waiting → working`.
- New mood `KiwiMood.waitingForApproval`.
- Local notification via `UNUserNotificationCenter` ("Agent is waiting for
  your approval") + `statusMessage` update.
- Guards: `schedulePlayfulMoment` must not override the waiting mood
  (`mood != .working && mood != .idle` already filters — verify), and the
  playful timer must be paused while waiting.

**Rendering (`KiwiPetView.swift`).**

- **Raised paw:** modify `drawPaws` (`:436`) — one front paw lifts
  (`-radius * 0.34`) with a gentle wave (`sin(time * 3)`), other paw stays.
- **`?` / `!` glyph above the head:** drawn as `Path` primitives (like
  `starPath` / `heartPath`), not `Text` — keeps the Canvas asset-free: `?` =
  small arc + dot, `!` = short line + dot. Choose glyph by state (waiting → `?`).
- **y/n bubble:** modeled on `PetBreakReminderBubble` (`:70`): ~228 pt wide,
  title "Agent is waiting", body "Your approval is needed (y/n)", buttons
  "Approve" and "Not now" (dismiss). Buttons only close the bubble locally —
  the agent still waits in its own terminal; the bubble is informational.
  Render inset in `PetDesktopView` (`:55`) like the break bubble.

**Event sources (all funnel into one handler).** URL scheme (`waiting`),
Webhook `POST /agent/waiting` (Feature 3), MCP `sweetnosleep_waiting` /
status parameter (Feature 2).

---

## 2. MCP server

**Goal.** Native tool-calling for MCP-compatible clients (Claude Code, Cursor,
opencode, Claude Desktop) without shell wrappers.

**Stack (verified against modelcontextprotocol.io).** Python 3.10+, `mcp` SDK
2.0.0+ (`uv add "mcp[cli]"`), `MCPServer("sweet-no-sleep")`, `@mcp.tool()`,
`mcp.run(transport="stdio")`. Tool schemas derive from type hints + docstrings.
**Hard rule: only stderr logging — `print()` corrupts JSON-RPC on stdout.**

**Location.** `mcp-server/` in the repo root (uv project, `pyproject.toml`).

**Tools.**

```python
@mcp.tool()
async def sweetnosleep_hold(reason: str, ttl_seconds: int = 900) -> str
@mcp.tool()
async def sweetnosleep_release(status: Literal["success", "failed"], summary: str | None = None) -> str
@mcp.tool()
async def sweetnosleep_waiting(waiting: bool) -> str   # Feature 1 from MCP
```

**Channel into the app.** Primary: POST to the local webhook (Feature 3) with
an internally generated session id — single entry point, no URL-scheme
duplication. Fallback when the webhook is disabled: `open sweetnosleep://…`.

**Client configs (documented in the plan doc).**

- `.cursor/mcp.json`: stdio, `command: "uv"`,
  `args: ["--directory", "${workspaceFolder}/mcp-server", "run", "server.py"]`.
- Claude Desktop `claude_desktop_config.json`: same shape, absolute path.
- opencode `opencode.json`: `mcp.servers.sweet-no-sleep.cmd`.

---

## 3. Local HTTP webhook (`127.0.0.1:18290`)

**Goal.** Loopback-only JSON endpoint for runtimes where `open sweetnosleep://`
is awkward (sandboxed Node/Python/Docker).

**Server options (constraint: no new runtime dependencies).**

- **A (recommended).** `Network.framework` `NWListener` — built in, async,
  bind `127.0.0.1:18290`, no libraries.
- B. raw BSD socket / `NSStream` — too low-level, rejected.
- C. GCDWebServer — external dependency, prohibited by the repo rule.

**Security (per MCP local-server-security: "Binding to 127.0.0.1 is not an
authentication boundary").**

- `POST` only; reject non-POST.
- **Bearer token required** (`Authorization: Bearer <token>`); token generated
  on first launch, displayed in Settings > Agent with a "Regenerate" button,
  stored in `UserDefaults` (no Keychain dependency needed for a local token).
- Origin/Host check against `127.0.0.1:18290`.
- JSON body: `{"session": "...", "reason": "..."}` — same schema as the URL
  events; share one parser with `handleAgentURL`.

**Lifecycle.** Listener starts when the agent bridge (or a dedicated "Agent
Webhook" toggle) is enabled; stopped in `shutdown()`.

---

## 4. Post-task grace period (1–5 min)

**Goal.** After the last agent lease ends, keep the Mac awake for a short,
configurable cooldown so background disk flushes, CI triggers, and Slack /
Telegram notifications can finish.

**Entry point.** `finishAwakeIfNoOtherSource` (`SweetNoSleepModel.swift:536`)
currently tears down immediately when no other source remains.

**Options.**

- **A (recommended).** If only agent leases were active and
  `completionAction == .allowNormalSleep`, do not release instantly: start a
  one-shot timer for the configured cooldown (1–5 min, default 1, `0` = off),
  keep `isKeepingAwake == true`, status "Agent finished — holding awake for
  N min". Any new agent event during the cooldown cancels the timer and resumes
  the lease flow.
- B. Hold the cooldown inside `PowerKeeper` — rejected: the model owns state.

**Settings.** New "Agent cooldown" stepper (0–5 min) in Settings > Agent.

---

## 5. Tooling presets

**Claude Code.** Project `.claude/settings.json` (committed, English). Draft
exists in `presets/claude-code-hooks.settings.json` (main working copy) but
must be corrected: wrapping *every* `PreToolUse/PostToolUse` in a fresh
`agent-session.sh` creates a lease per tool call and misses the LLM-thinking
gap. Correct lifecycle mapping:

| Event | Action |
|---|---|
| `SessionStart` / `UserPromptSubmit` | `start` (async hook) |
| `Stop` / `StopFailure` / `Notification(agent_completed)` | `done` / `failed` |
| `Notification(agent_needs_input | permission_prompt)` | `waiting` |
| `Notification(idle_prompt)` | optional: keep lease |

Uses `Scripts/agent-session.sh` + `Scripts/agent-event.sh` (add `waiting`
action; the draft already extends `agent-event.sh`).

**Aider.** Official hooks docs are unreachable from this machine (404 on every
path — likely regional CDN block). Do not invent syntax. Preset = documented
alias `alias aider='./Scripts/agent-session.sh aider -- aider'` plus an
install step; native hooks can be added later if the docs become reachable.

**Cursor / VS Code.** `tasks.json` draft exists (`presets/tasks.json`): build
and test wrapped in `agent-session.sh`. Ship as template.

**Installer.** `Scripts/install-presets.sh` — asks for target (repo root /
`~/.claude`, project `.cursor`), copies, validates JSON. Extend
`Scripts/test-agent-hooks.sh` to cover the `waiting` event.

---

## Open questions for the arena

1. **Indicator color default:** propose one (suggest `palette.accent`-derived);
   must be configurable via Settings.
2. **Multiple sessions:** one starving `waiting`, others working — indicator
   priority for `waiting` (suggested: waiting wins).
3. **Playful moments vs `waiting`:** waiting must suppress playful moments; the
   current guard checks `mood == .working || mood == .idle` — confirm it also
   holds when mood is `waitingForApproval`.
4. **Reduce Motion:** static light and static glyph, no pulse (matches the
   existing `reducedMotion` branch).
5. **Webhook token storage:** `UserDefaults` is acceptable for a localhost-only
   service; confirm no Keychain requirement.
6. **MCP server distribution:** repo-root `mcp-server/` as a uv project vs a
   single self-contained `server.py` file (no third-party deps, stdlib HTTP)? —
   recommend single-file stdlib HTTP fallback so the server works even without
   `uv`, with the uv project as the documented primary path.