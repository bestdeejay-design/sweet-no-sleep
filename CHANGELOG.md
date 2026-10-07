# Changelog

All notable changes to Sweet No Sleep — Kiwi Cat are documented here.
The format follows Keep a Changelog, versions follow Semantic Versioning.

## [Unreleased]

- Banner art slot reserved at `Resources/Art/banner.png` (README
  placeholder only, artwork delivery pending).
- No behavior changes; docs and repo hygiene only.

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
