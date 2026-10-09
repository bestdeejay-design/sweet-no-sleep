# Backlog — audit findings and prioritized tasks

Companion to `docs/ARCHITECTURE.md`. Audit date: 2026-10-09, after main
`87251fc` (all features merged: #16, #19, #20, #21-partial, #22; portfolio
case live on dajet.ru).

## Audit summary

Solid: awake-source model with real safety rails (cap, battery floor, lease
expiry, grace, watchdog), single event pipeline for all three channels,
bundle checks in CI, bilingual-safe localization tooling, layered sprite rig
with proven 45 pt legibility, overflow-safe dashboard footer.

Fragile spots found (details in tasks): assertion naming hides the active
source; dashboard height formula is state-combinatorics in disguise;
LaunchServices two-copy routing; webhook toggle/in-flight edge cases; no
UI tests; portfolio image swaps need manual cache-busting; docs scatter.

## P0 — correctness / user-visible bugs

- **B-01 · ✅ Verified fixed (2026-10-09).** Arena's audit commit (`09ed5a6`,
  issue #21 P0) reworked the bubble-dismiss path. Live Mac verification with
  a scripted Approve click at 45/132/170 pt, frames captured 0.15 s after the
  click (mid-resize) and settled: the pet renders complete in every frame,
  panel returns to petSide, waiting cue dismissed while the agent keeps
  waiting (badge stays amber). Evidence: maintainer acceptance session.
- **B-02 · Assertion naming.** With manual mode on, agent activity is
  invisible in `pmset` (first source names the assertion). *Accept:* either
  rename assertion when a new source class arrives, or expose per-source
  state in diagnostics; pmset-based verification documented in README.
- **B-03 · Dashboard height formula.** `640/660 + agentRowsHeight +
  diagnostics(110)` does not enumerate all state combinations (waiting reason
  wrap, 4 rows + diagnostics, focus + agents interplay). ScrollView saves
  usability but not layout polish. *Accept:* content never scrolls in
  default states; scrolling only as a last resort; visual pass of all 6
  state combinations.
- **B-04 · Two-copy LaunchServices routing.** `open sweetnosleep://` can wake
  and route to a stale copy (reproduced twice during acceptance). *Accept:*
  README runbook (lsregister -u/-f) + consider `LSCanRefuseMultipleCopies`
  / explicit bundle-id routing in `agent-event.sh` (`open -b`).

## P1 — robustness

- **B-05 · Webhook toggle races.** Rapid enable/disable, port occupied by a
  second instance at launch, token regeneration while requests in flight —
  code-reviewed by arena (#21) but no automated test. *Accept:* unit tests
  for server lifecycle + auth; manual checklist in CODE_AUDIT.
- **B-06 · MCP server untested in CI.** `mcp-server/server.py` has no tests
  and is not exercised by `check-project.sh`. *Accept:* smoke test (start,
  call tool, assert event delivery) wired into checks on macOS.
- **B-07 · Lease semantics divergence.** URL `heartbeat` from an unknown
  session starts a session; webhook heartbeat ignores unknown sessions.
  Intentional per code comment, but undocumented for users. *Accept:* one
  documented behavior (prefer webhook semantics), noted in README + presets.
- **B-08 · Skin pack migration path.** Format-1 packs render with the legacy
  pose; format-2 missing a rig layer is refused wholesale. *Accept:*
  `validate-skins.py` prints a migration hint; docs show a format-1→2 recipe.

## P2 — product polish

- **B-09 · Petting hearts on the sprite path.** Cheek-heart burst exists for
  procedural Kiwi; sprite cat draws hearts only during celebrations (PR #22
  claims parity — verify petting specifically). *Accept:* click/pet on sprite
  cat → hearts, both animation states.
- **B-10 · FPS overlay UX.** Hidden `SNSDebugFPSOverlay` exists; document it
  in CODE_AUDIT and add an on-screen hint when enabled.
- **B-11 · Break reminder on the sprite path.** Verify the break bubble sizes
  with the rig head layer at 45 pt (bubble +92 pt formula predates rig).
- **B-12 · Settings → skin cards inline refresh.** After adding a pack to the
  skins folder, the picker needs manual "Refresh list"; auto-detect folder
  change.
- **B-13 · Portfolio: case copy refresh.** dajet.ru case predates animation
  parity (#17) — mention layered rig/gaze/3 skins; refresh app-states strip
  (bump `?v=`) to the new build's visuals.

## P3 — infrastructure / docs

- **B-14 · UI test harness.** Zero automated UI tests; panel-wander smoke
  test is the only UI-adjacent check. *Accept:* XCUITest skeleton: menu opens,
  settings open, version footer renders, waiting bubble buttons exist.
- **B-15 · Unify state docs.** This file + CODE_AUDIT + SKIN_AUTHORING +
  README overlap; CODE_AUDIT should link here instead of duplicating state
  lists.
- **B-16 · Release engineering.** Version is 0.3.0 build-N ad-hoc; decide the
  1.0 checklist (Developer ID, notarization, app icon in Settings/About,
  Sparkle-style update story or explicit manual-update note).
- **B-17 · Localization rollout.** Catalog is English-only source (233 keys);
  `Scripts/localize.sh` exists but no locale ships. Decide target locales
  (RU first — maintainer audience) and wire Crowdin credentials in CI.
- **B-18 · ksu image cache convention.** Image swaps require `?v=N` bumps
  (learned twice); add a one-line note to ksu DESIGN_RULES and consider
  hashing filenames in the next restructure.

- **B-20 · Waiting-cue discoverability.** Live confusion: a stale hook session showed "1 waiting" but the user could not find the question — the bubble hides permanently after "Not now" (`dismissedWaitingIDs`) and dashboard rows show only short ids/states. *Accept:* dashboard row shows the question text; opening the dashboard re-arms the bubble for undismissed waiting sessions; "End agent sessions" confirm mentions which sessions end.

- **B-21 · Debug mood trigger.** Promo filming was painful: playful moods are random with a 60 s floor, so capturing the dance required blind waiting. *Accept:* hidden `sweetnosleep://debug/mood?mood=dancing&duration=4` (and `?list=1`) behind `agentBridge.enabled`; undocumented in README, documented in CODE_AUDIT; lets demos and tests trigger any `KiwiMood` deterministically.
- **B-22 · Native-speaker localization review.** PR #26 translations were written by the arena; RU/ES wording, gender assumptions (pet = masculine), and KO/ZH/JA nuance need a human pass. *Accept:* maintainer/native review notes applied; validator stays green.
- **B-23 · Notarized public builds.** v1.0.0 ships ad-hoc signed (right-click → Open). For wider distribution: Developer ID signing + notarization, or document the friction prominently; consider update delivery (manual re-download vs Sparkle). *Accept:* a release whose first launch needs no workaround, or a README banner that survives contact with a real user.
- **B-24 · Retire `localize.sh`.** The Crowdin-based script predates PR #26's direct-translation flow and can overwrite hand-edited catalog entries. *Accept:* script removed or clearly gated; README workflow updated to match how localization actually happens now.

## Suggested sequencing

1. B-01 (verify on Mac — 15 min) → B-03/B-02 (small fixes) → B-04 (runbook).
2. B-05–B-07 as one arena robustness order (tests included).
3. B-09–B-13 polish batch (arena, small diffs).
4. B-14/B-16 before calling anything 1.0; B-17 when the audience asks.
