# Changelog

All notable changes to Sweet No Sleep — Kiwi Cat are documented here.
The format follows Keep a Changelog, versions follow Semantic Versioning.

## [Unreleased]

- **Workspace consolidation:** the PR checkouts that sat next to the project
  (`sweet-no-sleep-pr9/-pr16/-pr22`) were git worktrees of this repository and
  are now relocated to `builds/{pr9,pr16,pr22}` with `git worktree move`; only
  `builds/README.md` is tracked. `docs/WORKSPACE.md` maps the layout, and the
  uncommitted diffs those checkouts carried are archived under
  `artifacts/2026-10-10-worktree-consolidation/`.
- **Presets:** previously uncommitted local presets are now in `presets/` —
  Aider (`.aider.conf.yml`, `aider-agent-wrapper.sh`, `aider-preset.md`), the
  `claude-code-hook.sh` dispatcher, a preset README, and the non-shipped
  `repo-scoped/` Claude Code variant. `presets/tasks.json` wraps `swift build`
  / `swift test` instead of the template's `npm` commands.
- **Localization in SwiftPM macOS bundles:** `Scripts/build-app.sh` seeds
  `Localizable.xcstrings` and the compiled tables into
  `<bundle>/Contents/Resources`, which is the resource path CFBundle uses once
  SwiftPM writes `Contents/Info.plist`. Without it `Bundle.module` could not
  see the catalog, `--localization-report` failed with "no keys found", and
  `check-project.sh` was red; all six locales now resolve all 242 keys at
  runtime.
- **Character source art:** `Resources/Characters/kot-arbuz/v2/` adds the
  maintainer-supplied update — the re-drawn master and an exploded view of the
  character with head, tail, body and the three legs as separate pieces.
- **Character animation loops (issue #27):** `Scripts/render-character-animations.py`
  renders both cats headlessly onto a transparent canvas — no display, no
  macOS capture. It ports `SpriteCharacterRenderer.swift` (Kot-Arbuz, over the
  committed sprite layers and the `pet.json` rig) and `KiwiPetView.drawPet`
  (Kiwi, pure geometry) to Pillow: breathing, blink, cursor gaze, walk cycle,
  dance, petting hearts, waiting glyph, agent badge with session pips, and the
  celebration effects. Output is one 420 × 420, 15 s, 12.5 fps loop per cat in
  animated WebP (full alpha) and GIF (fallback), covering idle → walk → dance →
  hearts → waiting → celebration.
- **Localization fix:** `Scripts/compile-localizations.py` now emits classic
  OpenStep `.strings` tables (`"key" = "value";`, UTF-16LE) instead of
  property lists. The CFBundle strings loader ignores a plist table, so
  `NSLocalizedString` silently returned the English key even though the
  file was in the bundle and `plutil` could read it. `L10n` ships a
  `--localization-report` self-check and `Scripts/verify-localizations.py`
  resolves every key of all six locales through `Bundle.module` in the
  assembled app on CI, so a format regression fails the build instead of
  shipping English.
- XCUITest skeleton under `Tests/UITests/` (B-14, not wired to CI).
  CODE_AUDIT defers state lists to BACKLOG (B-15). ksu cache-bust note
  in `docs/KSU_DESIGN_RULES.md` (B-18).
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
