# Sweet No Sleep — application logic, states, and functions

A single map of what the app does, every state it can be in, and how each
piece talks to the others. Maintainer-facing; user-facing behavior lives in
`README.md`. Line references drift — treat names as the source of truth.

## Module map

| File | Role |
| --- | --- |
| `SweetNoSleepModel.swift` | Single shared state machine: awake sources, sessions, moods, agent leases, timers, persistence (45 functions, ~30 `@Published` properties) |
| `SweetNoSleepApp.swift` | `MenuBarExtra` entry, dashboard (362 pt panel), signal handlers (SIGTERM/SIGINT), URL-event entry |
| `SettingsView.swift` | Settings window: Focus / Pet / Power tabs, version footer |
| `PowerKeeper.swift` | IOPM assertions, App Nap activity, sleep/wake notifications, immediate sleep, rearm timer, battery/watchdog pauses |
| `PowerSourceMonitor.swift`-backed logic (in model) | Battery floor: pause assertions on battery/power-source events |
| `PetPanel.swift` + `PetPanelLayout.swift` | Transparent NSPanel: sizing, dragging, roaming ("wander"), position persistence |
| `PanelOriginAnimator.swift` | Eased movement between origins (roam/drag), persisted `pet.panelOrigin` |
| `KiwiPetView.swift` | Procedural cat (Canvas): breathing, blink, gaze, cheeks, bubbles; waiting bubble UI |
| `SpriteCharacterRenderer.swift` | Sprite-pack cat: layered rig (head/legs/body/tail), vector eyes at rig anchors, gaze, celebration particles |
| `PetSkinDefinition.swift` | Skin pack schema: format 1 (palette) and format 2 (character rig), loading, validation, `characterName` persona |
| `CharacterSprite.swift` | Decoded sprite layers store (`CharacterSpriteStore.shared`) |
| `AgentIndicator.swift` | Chest badge light, session-count pips, waiting glyph, shared drawing API |
| `AgentWebhookServer.swift` | Loopback HTTP (127.0.0.1:18290, Bearer token) — same events as URL scheme |
| `PetShapes.swift`, `MediaAssets.swift` | Shared shapes (heart/leaf/star), bundled media lookup |
| `Localization.swift` + `Localizable.xcstrings` | `L10n.text/format`; English source catalog (233 keys) |
| `Scripts/*` | `agent-event.sh`, `agent-session.sh` (wrapper with heartbeats), `test-agent-hooks.sh`, `build-app.sh`, `check-project.sh`, `prepare-character-assets.py`, `validate-skins.py`, `validate-localization.py`, `validate-media.py`, `render-media.sh` |
| `mcp-server/server.py` | MCP server (F2) exposing agent events to MCP-capable clients |
| `presets/` | Hook presets for Claude Code / generic hooks / VS Code tasks |
| `builds/` | Relocated PR worktrees, ignored by git except `builds/README.md` — see `docs/WORKSPACE.md` |

## Awake sources (who keeps the Mac awake)

The model has exactly three sources; any active source holds assertions via
`PowerKeeper.begin`. Assertion names: `manual mode`, `focus session`,
`AI agent work` (created only if `!isKeepingAwake`, i.e. the first source to
arrive names the assertion — a later source does not rename it; pmset shows
only the first).

1. **Manual awake** — `startManualAwake()` / `setKeepAwake(true)`. No timer.
   Optional per-session completion action: release, or `requestImmediateSleep`
   (confirmed; token-guarded `pendingImmediateSleepToken`).
2. **Focus session** — `startFocusSession()`: 15–240 min, `sessionTimer` 1 s
   tick, `remainingSeconds`, completion action chosen in advance. On finish:
   release or immediate sleep (with confirmation dialog).
3. **Agent sessions** — N concurrent leases (URL scheme, webhook, or MCP),
   each with a 3-minute lease renewed by `start`/`heartbeat`/`waiting`;
   `agentLeaseTimer` prunes every 15 s. `waiting` keeps the lease alive while
   the question is pending but the global awake cap still applies.

Safety rails (all in model/PowerKeeper):
- **Continuous awake cap** `continuousAwakeCapHours` (0–12, default 4):
  `holdStartUptime` + `hasCapTripped` force a release when held too long —
  applies to *all* sources, including waiting agents.
- **Battery floor** `batteryFloorPercent` (0–50, default 20): on power-source
  change to battery/below floor → `pauseAssertions`, auto `resumeAssertions`
  when power returns; mood → `.resting`, status message explains.
- **Grace after wake**: taps within a grace window after system wake are
  ignored (a click meant to dismiss the lock screen must not pet the cat).
- **Heartbeat timer** (1 s tick drives session countdown/heartbeats re-arm).
- Watchdog pause/re-arm (`rearmTimer`) and will-sleep/wake notifications.

## Mood machine (`KiwiMood` — 11 states)

`idle, working, celebrating, dancing, stretching, curious, breakReminder,
resting, dragging, walking, waitingForApproval`

- `baseMood()` derives the resting pose: waiting agent → `waitingForApproval`;
  keeping awake → `working`; else `idle` (or `resting` after battery pause).
- **Playful moments** (`playfulTimer`, interval 60–120 s, default 90):
  weighted random `dancing` / `stretching` / `curious` (user-tunable weights
  0–10 each); temporary via `setTemporaryMood` then back to base.
- **Break reminders** (`breakTimer`, 10–60 min, default 25): `breakReminder`
  mood + bubble; snooze/dismiss/disable.
- **Walking**: roaming strolls set `.walking` while the panel animates.
- **Dragging**: pointer-drag on the pet.
- **Resting**: battery floor / animations-off resting pose.
- All moods render on both drawing paths (procedural Kiwi and sprite cat).

## Agent awareness (F0/F1/F5)

- Sessions: `agentSessions[sessionID] = AgentSessionState(status, startedAt,
  lastActivityAt, expiry, reason)`; status `working | waiting`.
- `agentLightState`: `.off` unless indicator enabled and sessions exist;
  `.waiting` wins over `.working`.
- Chest badge (green/amber) + pips (1/session, max 5, then `+`).
- Waiting: amber light, raised paw, `?`/`!` glyph, y/n bubble with reason;
  bubble buttons only dismiss the cue (`dismissWaitingCue`) — the agent keeps
  waiting in its own window; dashboard shows per-session rows (waiting first,
  then oldest), `TimelineView` refresh 5 s.
- Lease expiry: a waiting session still expires (lease is renewed only by
  events); global cap still applies → no infinite "agent holds Mac awake".

## Delivery channels (all funnel into `handleAgentEvent`)

1. URL scheme `sweetnosleep://agent/<action>?session=&reason=` (opt-in
   `agentBridge.enabled`; LaunchServices routes to *a* registered copy — see
   backlog B-04).
2. Webhook `POST http://127.0.0.1:18290/agent/<action>` (opt-in, Bearer
   token, 32-hex, regenerable; 401 on bad/missing; bind-retry, zombie-listener
   stop fix).
3. MCP server (`mcp-server/server.py`) for MCP clients.
4. Wrapper `Scripts/agent-session.sh <id> -- <cmd>`: start, heartbeats,
   done/failed on exit — for agents without hooks.

Actions: `start` (create/renew working), `heartbeat` (renew; unknown session
ignored on webhook, treated as start on URL), `waiting` (renew as waiting +
reason ≤200 chars), `done`/`failed` (finish; mood reset, celebration on
success path).

## Rendering pipeline

- Pet panel: fixed-size transparent panel `petSide = petSize + 48`
  (45–170 pt), waiting bubble adds +92 (width ≥ bubble width), break bubble
  similar. `PanelContentSizeReporter` feeds size changes back.
- Procedural path (`KiwiPetView`): `TimelineView(.animation)` at display
  refresh (60 fps+), `cursorGaze` follows pointer, blink cadence ~4.6 s,
  Reduce Motion respected.
- Sprite path (`SpriteCharacterRenderer`): format-2 packs (head/legs×3/
  body/tail + rig anchors incl. eye sockets, pivots); format-1 packs load
  with the legacy pose. Vector eyes (outline ellipse + white shine, gaze
  offset) drawn at rig anchors; painted eyes are inpainted out of the art.
- FPS debug overlay: `defaults write <bundle> SNSDebugFPSOverlay -bool true`.
- Skins: 3 procedural Kiwi-family packs + 3 Kot-Arbuz packs (base/moon/
  strawberry, palette+effect variants: leaves / moonDust / berryHearts).
  Persona: `characterName` (format 2) → every user-facing string; procedural
  packs fall back to "Kiwi".

## Persistence (`UserDefaults`, bundle `com.sweetnosleep.kiwicat`)

~30 keys: session (`session.selectedMinutes`, `session.completionAction`),
pet (`pet.size/visible/alwaysOnTop/roamingEnabled/animationsEnabled`,
`pet.skin`, `pet.panelOrigin` array), playful weights/interval, break
reminders, power (`power.keepDisplayAwake`, `power.resumeOnLaunch`,
`power.batteryFloorPercent`, `power.continuousAwakeCapHours`), agent bridge
(`agentBridge.enabled/indicatorEnabled`), webhook (`agent.webhookEnabled`,
`agent.webhookToken`), diagnostics.

## UI surfaces

- Menu-bar dashboard: header status, companion card, power card, one of
  {running session | agent sessions | focus starter}, diagnostics (expandable),
  footer Hide/Settings/Quit. Middle cards scroll (overflow-safe footer).
- Pet panel: the cat + bubbles (waiting y/n, break reminder).
- Settings: Focus / Pet / Power tabs; hooks usage snippet with Copy; webhook
  card; version footer `Version X (build N)` (auto-incremented by build).
- Launch at login via SMAppService (Settings → Power).

## Build / release

`Scripts/build-app.sh` → `dist/Sweet No Sleep — Kiwi Cat.app` (ad-hoc sign,
CFBundleVersion auto-increment). `check-project.sh` = shell syntax +
localization (233) + media + skins + character assets + agent hooks (10
events) + swift build + panel-wander smoke test. CI: `.github/workflows/
macos.yml` builds and verifies bundle contents. Portfolio site: `ksu` repo →
dajet.ru (Pages), case `#project-16`; image swaps must bump `?v=N` (app-states strip is currently `?v=4`). See `docs/PORTFOLIO_CASE.md`.
