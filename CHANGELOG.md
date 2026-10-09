# Changelog

All notable changes to Sweet No Sleep — Kiwi Cat are documented here.
The format follows Keep a Changelog, versions follow Semantic Versioning.

## [Unreleased]

- Petting hearts on the sprite path in both animation states (B-09). FPS
  overlay on-screen hint (B-10). Break/waiting bubbles sized for the 45 pt
  rig (B-11). Skin picker auto-reloads the user folder (B-12). Portfolio
  case copy + `app-states.jpg?v=4` (B-13).
- Assertion names follow the active source class (manual/focus/agent);
  Hold diagnostics lists awake sources (B-02). Dashboard height covers
  the six default state combinations (B-03). Agent events route with
  `open -b` and `LSMultipleInstancesProhibited` (B-04). Webhook auth
  tests and MCP smoke test in `check-project.sh` (B-05, B-06). Heartbeat
  never opens a lease (B-07). Skin validator prints a format-1→2
  migration hint (B-08).
- README "The cats": Kiwi (the original, three palette looks) and
  Kot-Arbuz (layered sprite character, leaf celebrations, agent
  awareness) as two characters with their own names, with the skin
  card preview inline and a link to the character case on dajet.ru.
- Final release media pack (issue #5 decision): banner, Open Graph
  image, app icon and skin preview SVG sources in `Resources/Art/`
  with rendered PNGs in `Resources/Art/Rendered/`; README ships the
  banner and media links; macOS CI uploads the media kit as an
  artifact and validates renders against golden SHA-256 pins.
- Pet size slider spans 45–170 pt in 1 pt steps with a
  "45 pt - compact" end label (was 90–170 pt in 2 pt steps).
- Release community files: MIT `LICENSE`, `CODE_OF_CONDUCT.md`,
  `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md`, bug/feature issue
  forms and a pull request template.

## [0.1.0] - 2026-10-07

First public checkout: a native macOS focus companion with a floating pet.

- Floating pet panel: transparent `NSPanel`, always-on-top option,
  cross-Spaces support, persisted position, drag-to-move, eased
  roaming strolls, click reactions, pointer-following gaze.
- PowerKeeper: App Nap friendly activity plus `PreventUserIdleSystemSleep`
  assertions with separate display-sleep control and launch-at-login support.
- Focus sessions: timed sessions from 15 minutes to 4 hours plus manual
  awake mode; completion either releases the assertion or, with explicit
  per-session confirmation, puts the Mac to sleep immediately.
- Three JSON skin packs: Kiwi, Moonlight, Strawberry, each with its own
  palette, motion profile, and celebration effect; user packs loadable
  without app source changes.
- Emotions and rhythm: breathing, blinking, tail sway, playful moments about
  every 3.5-6.5 minutes, gentle 25-minute break reminders with snooze and
  dismiss; system Reduce Motion respected.
- Agent hooks: opt-in local URL-scheme bridge (`sweetnosleep://`) with
  `start`, 60-second `heartbeat` (3-minute lease), terminal `done` / `failed`
  events via `Scripts/agent-event.sh` and `Scripts/agent-session.sh`.
- Localization infra: English source catalog in
  `Sources/SweetNoSleep/Localizable.xcstrings` behind `L10n`, with
  `Scripts/validate-localization.py` parity checks and Crowdin-based
  `Scripts/localize.sh` generation for future locales.
- Tooling: `Scripts/build-app.sh` local `.app` assembly with ad-hoc signing,
  `Scripts/check-project.sh` portable checks plus `swift build` and
  panel-motion smoke test on macOS, `pmset` assertion verification flow.
