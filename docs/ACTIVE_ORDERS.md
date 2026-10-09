# Active work orders — 2026-10-09

Two open orders for the arena. Both base on current `main`. Standing rules
from issue #1 apply (arena branches only, PR against `main`, no merge,
HEAD + CI link in the reply).

## Order 1 — fix localization table format (PR #26 follow-up)

Status: review findings posted at
https://github.com/bestdeejay-design/sweet-no-sleep/pull/26#issuecomment-6077330831

- Translations (ru/es/ko/zh-Hans/ja) are merged but never load at runtime:
  `compile-localizations.py` emits UTF-16 XML plists; the CFBundle strings
  loader rejects them (verified on macOS: table readable via
  `NSDictionary(contentsOfFile:)`, 240 keys, but `NSLocalizedString` returns
  the English key; `plutil -convert binary1` does not help).
- Fix: emit classic OpenStep `.strings` (`"key" = "value";`, UTF-16LE), then
  extend the CI verify step to run a real `NSLocalizedString` lookup through
  `Bundle.module` (not just table presence) for every locale.
- Do not touch the translations themselves.

## Order 2 — headless animation render, transparent background (issue #27)

Status: approach changed — see
https://github.com/bestdeejay-design/sweet-no-sleep/issues/27#issuecomment-6077237657

- No Mac needed: render both cats headlessly in your environment with a
  transparent background (WebP/GIF), 15 s loops, one per cat.
- Kot-Arbuz: port the mood/animation math from `SpriteCharacterRenderer.swift`
  to PIL over the committed layers (`tail/legs-a/legs-b/legs-c/body/head`)
  and the `pet.json` rig: breathing, blink, cursor-gaze offsets, walk cycle,
  dance (sway + hop + paw bounce), waiting glyph, agent badge + pips,
  celebration hearts.
- Kiwi: port `KiwiPetView.swift` geometry to PIL, same shot list — or fall
  back to the (cancelled) capture-script path for Kiwi only, your call.
- Deliver: renderer script + rendered files + PR. Shot list per cat:
  idle blink/gaze → walk → dance → hearts → waiting glyph → celebration.
- The capture-script part of the original order is cancelled; keep
  `Scripts/demo-*.swift` (useful later).

## Order 3 — Batch D from `docs/BACKLOG.md` (B-20, B-21, B-24)

Added 2026-10-09 after live use. Small, scoped fixes:

- **B-20:** waiting-cue discoverability — dashboard row shows the question
  text; reopening the dashboard re-arms the bubble for undismissed waiting
  sessions; "End agent sessions" lists what it ends.
- **B-21:** hidden `sweetnosleep://debug/mood` trigger (see backlog entry).
- **B-24:** retire or gate `localize.sh` (superseded by direct translation).

B-22 (native review) stays with the maintainer. One PR, keep
`check-project.sh` green.
