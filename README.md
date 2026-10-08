# Sweet No Sleep — Kiwi Cat

A native macOS companion that keeps your Mac awake during long work
sessions and makes it pleasant to look at. A small floating pet,
Kiwi, lives on your desktop, reacts to what you do, and holds a
power assertion while you (or your coding agent) need the machine
to stay awake.

No menus to learn, no accounts, no network calls. Just a pet that
watches over your focus time.

## Release media

![Sweet No Sleep release banner: Keep the Mac awake while the work finishes, with Kiwi beside a focus-session dashboard preview](Resources/Art/Rendered/banner.png)

[Download the 1280 × 640 banner PNG](Resources/Art/Rendered/banner.png) · [editable banner SVG](Resources/Art/banner.svg) · [Open Graph SVG](Resources/Art/og-image.svg). The SVG files are the editable sources; `Scripts/render-media.sh` rebuilds raster assets on macOS. A successful macOS CI push commits the generated images to the task branch and uploads the media kit as an artifact.

## Features

- **Kiwi, the floating pet.** A transparent always-on-top panel with
  a hand-drawn Canvas pet: breathing, blinking, a swaying tail,
  pointer-following eyes, click reactions, and drag-to-move.
  Stays across Spaces, remembers its position, never steals focus
  from your editor.
- **Focus sessions and manual awake mode.** Run a timed session from
  15 minutes to 4 hours, or flip manual awake mode on with no timer.
  On completion, either release the assertion and let macOS resume
  its normal sleep settings, or put the Mac to sleep immediately
  (with per-session confirmation).
- **Three built-in skins.** Kiwi, Moonlight, and Strawberry ship as
  JSON packs with their own palettes, motion profiles, and
  celebration effects. Add your own packs without touching app
  source; see `docs/SKIN_AUTHORING.md`.
- **Emotions and playful moments.** Kiwi dances, stretches, and gets
  curious roughly every 3.5-6.5 minutes during a session. Gentle
  break reminders arrive every 25 minutes by default (snooze,
  dismiss, or disable). Respects system Reduce Motion.
- **Agent bridge (opt-in, local only).** An off-by-default URL-scheme
  bridge (`sweetnosleep://`) lets coding agents and IDE hooks hold
  awake with `start`, minute-interval `heartbeat`, `waiting` for
  approval pauses, and terminal `done` / `failed` events. A 3-minute
  heartbeat lease means a lost hook never keeps the Mac awake forever.
  Waiting sessions show Kiwi's attentive pose with an amber chest light
  and a y/n bubble. Optional loopback webhook (`127.0.0.1:18290`,
  bearer token), stdlib-only MCP server (`mcp-server/server.py`), and
  a post-agent grace period (1-5 min) are included; see `presets/` and
  `Scripts/install-presets.sh`.
- **Power done right.** App Nap friendly activity plus
  `PreventUserIdleSystemSleep` assertions. Optional separate display
  control: keep the Mac awake while allowing the display to sleep.
  Launch at login supported.

## Install and run

Requirements: macOS 14 or later, Xcode 16 or later with the
Swift 5.9 toolchain.

```bash
# Run straight from source
swift run --package-path /path/to/sweet-no-sleep

# Or build a local .app bundle
cd /path/to/sweet-no-sleep
./Scripts/build-app.sh
open "dist/Sweet No Sleep — Kiwi Cat.app"
```

`Scripts/build-app.sh` compiles a release binary, assembles a
minimal `.app`, copies skin and localization resources, and ad-hoc
signs it for local use. Keep the app at a stable path if you enable
launch at login. Public distribution needs Developer ID signing,
notarization, and an app icon.

Validate the checkout before building:

```bash
./Scripts/check-project.sh
```

On macOS this also runs `swift build` and a borderless-panel
roaming smoke test. See `docs/CODE_AUDIT.md` for the Mac acceptance
checklist.

## Settings overview

Open the menu-bar item and choose **Settings** (the app window, not
a macOS system pane). Three sections:

- **Focus.** Session duration, completion behavior (release
  assertion vs. immediate sleep), and manual awake mode.
- **Pet.** Skin picker, size (45-170 pt), visibility, window level,
  screen roaming (off by default; first stroll about 3 seconds
  after enabling, then roughly every 28 seconds), animation,
  playful moments, and break reminders. Drag Kiwi to reposition.
- **Power.** Display sleep control, battery safety floor, continuous
  awake cap, hold diagnostics, opt-in agent hooks
  (**Settings -> Power -> Allow events from local hooks**), and
  launch at login.

To install a custom skin: **Settings -> Pet -> Open skins folder**,
copy in a directory containing `skin.json`, press **Refresh list**,
and pick its card.

## Verify sleep protection

Start manual awake mode or a focus session, then run:

```bash
pmset -g assertions | grep "pid $(pgrep -x SweetNoSleep)"
```

or:

```bash
pmset -g assertions | grep -A4 -B2 -i "Sweet No Sleep"
```

You should see the app's `PreventUserIdleSystemSleep` assertion,
plus a display assertion if **Keep the display on during a session**
is enabled. Note the `Timeout` field (assertions are created with
a 120-second fail-safe kernel timeout and automatically re-armed at
~90 seconds). Stop the session and confirm the entries disappear.

## AI agents and sleep

Sleep protection covers **idle system sleep** only. It cannot
override a user sleep command, a closed MacBook lid, critical
battery shutdown, or other macOS policies.

The app never guesses agent state from open editor windows. Instead,
use the wrapper for agent commands (sends `start`, heartbeats every
60 seconds, then `done` or `failed`):

```bash
./Scripts/agent-session.sh my-agent-123 -- ./run-my-agent.sh --your-args
```

Or call lifecycle events directly from IDE hook callbacks, reusing
one session ID and heartbeating about once a minute:

```bash
./Scripts/agent-event.sh start "$SESSION_ID"
./Scripts/agent-event.sh heartbeat "$SESSION_ID"
./Scripts/agent-event.sh waiting "$SESSION_ID" "need approval for rm -rf"  # pauses work, Kiwi turns attentive
./Scripts/agent-event.sh done "$SESSION_ID"    # success
./Scripts/agent-event.sh failed "$SESSION_ID"  # error or cancellation
```

For sandboxed runners that cannot open URL schemes, enable
**Settings -> Power -> Local webhook** and POST JSON instead:

```bash
curl -X POST http://127.0.0.1:18290/agent/waiting \
  -H "Host: 127.0.0.1:18290" \
  -H "Authorization: Bearer $SWEET_NOSLEEP_WEBHOOK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"session":"my-agent-123","reason":"need approval"}'
```

MCP-compatible clients can use the stdlib-only server (no pip
dependencies, logs to stderr, falls back to the URL scheme when the
webhook is unreachable):

```bash
SWEET_NOSLEEP_WEBHOOK_TOKEN="<token from Settings>" python3 mcp-server/server.py
```

Out-of-the-box presets live in `presets/` (Claude Code hooks,
Cursor/VS Code tasks). Install interactively with
`./Scripts/install-presets.sh`.

The URL bridge is unauthenticated local IPC: any local process that
can open the URL scheme may send events. Enable it only for trusted
hooks. The webhook adds a bearer token and strict Host/Origin checks
but is still loopback-only local IPC, not a security boundary.
Agent events can release an assertion but never trigger immediate
sleep. After the last agent finishes, an optional grace period
(Settings -> Power -> Post-agent grace period, default 1 min) holds
awake briefly when the after-session action is Allow normal sleep.

## Localization

`Sources/SweetNoSleep/Localizable.xcstrings` is the English source
catalog; visible strings go through `L10n.text` / `L10n.format`.
Checks:

```bash
python3 Scripts/validate-skins.py /path/to/a-skin-pack
python3 Scripts/validate-localization.py
```

Extra locales are generated via `Scripts/localize.sh` (Crowdin CLI,
CI-supplied credentials), never hand-edited. This checkout ships
English source strings only.

## Docs

- `docs/RESEARCH.md` — design notes, power-management limits,
  agent integration guidance, roadmap.
- `docs/SKIN_AUTHORING.md` — skin pack schema and installation.
- `docs/PET_DRAWING_GUIDE.md` — how the pet is drawn.
- `docs/CODE_AUDIT.md` — audit findings and Mac acceptance
  checklist.
- `docs/IMPROVEMENTS.md` — prioritized improvement ideas with
  proposed solutions and acceptance criteria.

## Project layout

```text
Sources/SweetNoSleep/
  SweetNoSleepApp.swift      # MenuBarExtra, lifecycle, dashboard
  SweetNoSleepModel.swift    # shared state, sessions, reminders, skins
  AgentWebhookServer.swift   # loopback HTTP webhook (Network.framework)
  PetSkinDefinition.swift    # JSON schema and pack loading
  KiwiPetView.swift          # Canvas pet, gaze, reactions
  PetPanel.swift             # transparent NSPanel, roaming, position
  PanelOriginAnimator.swift  # eased movement, persisted origin
  PowerKeeper.swift          # App Nap activity, IOPM assertions
  SettingsView.swift         # Focus, Pet, Power settings
  Localization.swift         # NSLocalizedString access
  Localizable.xcstrings      # English source strings
Resources/PetSkins/          # kiwi, moonlight, strawberry packs
Resources/Art/               # pet-template.svg, banner art slot
Scripts/build-app.sh         # .app bundle assembly
Scripts/check-project.sh     # portable checks + swift build on Mac
Scripts/agent-event.sh       # single agent lifecycle event
Scripts/agent-session.sh     # wrapped command with heartbeat
Scripts/install-presets.sh   # interactive preset installer
mcp-server/server.py         # stdlib-only MCP server (stdio)
presets/                     # Claude Code hooks, Cursor/VS Code tasks
```

---

Built by Axiiom Studio (https://axiiom.ru), part of https://dajet.ru.
