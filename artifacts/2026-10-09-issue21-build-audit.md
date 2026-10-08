# Full-featured build audit - issue #21 - 2026-10-09

**Work order:** [issue #21](https://github.com/bestdeejay-design/sweet-no-sleep/issues/21)
"full-featured build audit - P0 Approve-bubble clip + webhook/MCP/dashboard sweep".
Base: `main` @ `df28c13` (PR #20 webhook + MCP merged), read as one codebase
together with this session's branch. Linux environment; macOS CI runs the build
and the new unit test; live Mac acceptance stays with the maintainer.

## P0 - Approve button clips the pet: root cause and fix

**Reproduced by code trace, not by clicking.** The bubble and the panel frame
disagreed about whether a dismissed cue occupies space:

- `KiwiPetView.swift` (`PetDesktopView.bubbleHeight/bubbleWidth/body`, old lines
  55-75) keyed the bubble on `model.hasWaitingAgent`, which ignores
  `dismissedWaitingIDs`;
- `PetPanel.swift` (`PetPanelController` Combine sink, old lines 147-158) sized
  the panel from the dismissal-aware session list and resized **synchronously
  from `@Published` willSet**, i.e. one runloop turn before SwiftUI re-laid out.

Clicking Approve therefore shrank the panel around a bubble the view still
showed: a 92 pt stack inside a panel that had lost 92 pt, so the sprite drew
outside the panel bounds and was clipped until the session left `waiting`.

**Fix (three parts, all in this PR):**

1. One predicate: the view now uses `model.showsWaitingBubble`
   (`KiwiPetView.swift`), the same dismissal-aware flag the controller uses.
2. One geometry: new `Sources/SweetNoSleep/PetPanelLayout.swift` is the single
   source of truth for pet side, bubble heights/widths, content size and gaze
   inset; `PetDesktopView`, `KiwiPetView.topInset`, `PetLayerHitTestView` and
   `PetPanelController.panelSize` all call into it.
3. Atomic resize: the panel no longer resizes from willSet. `PetDesktopView`
   reports its laid-out size through `PanelContentSizeReporter`
   (`updateNSView`, i.e. inside the SwiftUI update transaction that added or
   removed the bubble) and `PetPanelController.applyContentSize` sets the frame
   there. AppKit frame and SwiftUI content move in the same update, so there is
   no frame where the sprite draws outside the panel.

**Unit test:** `Scripts/test-panel-layout.sh` (+ `test-panel-layout.swift`)
compiles `PetPanelLayout.swift` headlessly with `swiftc` on macOS and pins the
truth table, including the regression itself: `showsWaitingBubble == false`
with a still-waiting session must yield a bubble-free content size. Wired into
`check-project.sh` (Darwin branch); skipped off-Darwin like the Swift build.

## P1 sweep - findings

| # | Area | Finding | Severity | Status |
| --- | --- | --- | --- | --- |
| 1 | Webhook | No per-connection deadline: a stalled or slow-loris client parked a listener queue slot forever | medium | Fixed: 15 s watchdog per connection, `AgentWebhookServer.swift` `accept`/`drop` |
| 2 | Webhook | Toggling the bridge off mid-flight still let an in-flight request deliver its event | medium | Fixed: connections tracked on the server queue and cancelled in `stop()` |
| 3 | Webhook | The 5 s send-safety cancel ran on the main queue and never untracked the connection | low | Fixed: hops through `drop()` on the server queue |
| 4 | Webhook | Regenerating the token did not restart the listener, so Settings showed a token the running server did not validate | medium | Fixed: `regenerateWebhookToken()` bounces the server when enabled |
| 5 | Webhook | HTTP edge cases (partial reads, >8 KB headers, >4 KB body, malformed JSON, missing session, non-POST, wrong Host/Origin, bad token, unknown path, `Expect: 100-continue`) | - | Verified by read-through: 413/400/405/403/401/404 handled, one request per connection. Chunked bodies are unsupported and answer 400 - documented limitation, all in-repo clients send Content-Length |
| 6 | Webhook | Token compare is constant-time but returns early on length mismatch (length leak) | info | Accepted: 32-hex loopback bearer token, length is not secret |
| 7 | Pipeline | A waiting session expired on the 180 s working lease although the agent cannot heartbeat while blocked on a human answer - cue and sleep protection dropped mid-question | medium | Fixed: `waitingLeaseTimeout` 600 s for `waiting` leases, refreshed by every waiting event |
| 8 | Pipeline | Reason sanitising, duplicate sessions, heartbeat-unknown-session self-heal, waiting->working transition | - | Verified: `sanitizedReason` (control chars, 200 chars) applied on both channels; `dismissedWaitingIDs` cleared when a session returns to work |
| 9 | Dashboard | `agentRowsHeight` added agent-row space even while a focus session replaces the agent card | low | Fixed: guard `!model.isFocusSession` |
| 10 | Dashboard | Formula vs content states (>4 sessions, wrapped waiting reason, expanded diagnostics) | info | Not a clip since PR #19's ScrollView: overflow scrolls, footer stays reachable. Left as designed |
| 11 | Sprite path | Layer PNG dimensions were never checked against `pet.json` `canvas` at load; a wrong-sized user pack would draw stretched | medium | Fixed: `CharacterSpriteStore.cgImage(at:canvas:)` refuses non-conforming layers, matching `validate-skins.py` |
| 12 | Sprite path | Corrupt `pet.json` / missing rig layer handling | - | Verified: manifest decode failure or any missing rig layer refuses the whole pack (no half cat) |
| 13 | Persona | Menu bar title hardcoded `L10n.text("Kiwi")` | medium | Fixed: `MenuBarExtra(model.characterName, ...)`; all other user-visible strings already route through `characterName`/`personaName` |
| 14 | Localization | `%@`/`%d` arity at every `L10n.format` call site | - | Checked programmatically: 78 call sites against the xcstrings placeholders, zero mismatches; `validate-localization.py` green (232 keys) |
| 15 | Concurrency | Webhook closures hop to `@MainActor` via `Task`; all listener state confined to the serial queue; `stop()` is synchronous so no zombie listener; dashboard owns no timers; model timers invalidated on stop | - | Verified, no change needed |
| 16 | MCP server | `mcp-server/server.py` hardcodes `Host: 127.0.0.1:18290` even when `SWEET_NOSLEEP_WEBHOOK_URL` is overridden | info | Accepted: the listener only ever binds 127.0.0.1:18290 and rejects other Host headers by design (DNS-rebinding protection) |

## Verification

- Linux: `./Scripts/check-project.sh` green (232 localization keys, 6 skin
  manifests, hook smoke tests), `grep -rn '[А-Яа-я]' Sources/` empty, Swift
  files parse clean.
- macOS CI: full `check-project.sh` including the Swift build **and the new
  `test-panel-layout.sh`**, plus `build-app.sh release` - link in the PR thread.
- Maintainer (Mac): waiting bubble -> Approve -> pet never clips (recording);
  `curl -X POST http://127.0.0.1:18290/agent/start` with/without token ->
  200/401; second instance port conflict -> clean Settings error, no crash.
