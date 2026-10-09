# Sweet No Sleep code audit

Audit date: October 6, 2026. Reviewed the application source, settings persistence, skin library, pet renderer, floating panel, power lifecycle, local bridge and shell hooks, app packaging, JSON manifests, and project documentation.

## Summary

Several cross-feature defects were found and fixed. The core flows remain: manual awake mode, timed focus sessions, agent leases with heartbeat/TTL, user skin packs, the transparent pet panel, and configurable behavior.

The current workspace is Linux and does not provide Swift/Xcode or the macOS SDK. GitHub Actions has verified the native build, release app packaging, and a real borderless-panel movement smoke test on macOS. Full app interaction, assertion counting on the user's Mac, and repeated Settings-window opening still require the manual acceptance checklist below.

## Findings and fixes

1. **The break reminder could appear without resizing the pet window.** Combine's `@Published` emits from `willSet`; the panel subscriber re-read the old `isBreakDue` value. It now uses the emitted value when updating panel dimensions and hit testing.
2. **Skin discovery depended on the process working directory.** Running `swift run --package-path` from a different directory could miss checkout packs. The loader now searches app-bundle resources, source and executable ancestors, and the user pack folder. User packs can still intentionally override a bundled ID.
3. **The menu preview tracked the pointer relative to the menu window.** Cursor tracking is disabled for the menu preview; the desktop pet retains pointer-following eyes.
4. **Reduce Motion did not suppress every celebration effect.** Particle twinkle and leaf drift are static under system Reduce Motion or when animation is disabled. Automatic screen roaming also respects system Reduce Motion.
5. **Pet moods could conflict.** A click, drag release, heartbeat, or stroll could replace a due break expression. Break state now takes priority after temporary reactions; roaming does not start during breaks or transient moods.
6. **Agent heartbeats could clear a display-assertion warning.** Heartbeats no longer clear that warning. If macOS cannot restore the optional display assertion after wake, the app reports it while keeping system-sleep protection active.
7. **A delayed immediate-sleep request could race with new work.** A short delay lets macOS observe the released assertion. Starting another manual, focus, or agent session in that interval now cancels the request, and the callback checks active sources again.
8. **Portable validation was missing.** Added skin-manifest validation, mocked agent-hook smoke tests, and a single project check script.
9. **PowerKeeper cleanup conflicted with MainActor isolation in `deinit`.** Removed the actor-isolated deinitializer and added explicit `shutdown()` cleanup, called from the app termination lifecycle. Process termination also releases any OS-owned IOKit assertions if the app is forcibly stopped.
10. **Settings did not open reliably from the menu-bar dashboard.** Replaced `SettingsLink` with the SwiftUI `openSettings` environment action and explicit app activation.
11. **User-visible text was embedded directly in Russian source strings.** The UI now uses an English-source `Localizable.xcstrings` catalog through `NSLocalizedString`; the Swift source tree is English-only. A localization validator checks source/catalog key parity. Other translations must be generated through the localization workflow, not hand-edited.
12. **Screen roaming was difficult to discover.** Settings and README document **Settings → Pet → Behavior**; the first stroll now starts after about 3 seconds, then repeats about every 28 seconds.
13. **Timer callbacks crossed into main-actor state from sendable closures.** Timer work now hops explicitly onto `MainActor`, including roaming, countdown, break, lease, and mood updates, to keep the callbacks safe under Swift's stricter concurrency checking.
14. **Roaming's animation completion was a false positive.** `NSAnimationContext` reported completion for `panel.animator().setFrameOrigin` without moving a borderless panel. Roaming now uses a 48-step eased animator that calls `setFrameOrigin` directly and persists `pet.panelOrigin` at every step. A macOS smoke test checks intermediate movement and the saved final origin.
15. **Sleep protection could show duplicate system assertions.** `ProcessInfo.userInitiated` also prevents idle system sleep, duplicating the explicit IOPM assertion. The activity now uses `userInitiatedAllowingIdleSystemSleep` to avoid App Nap while allowing the single IOPM system assertion to own sleep prevention. Repeated `begin()` calls coalesce and only reconcile the optional display assertion.
16. **Reopening Settings from the accessory menu could be flaky.** The settings action is now scheduled for the next main-actor turn after activation, then the app is activated again before invoking `openSettings()`.
17. **Self-expiring fail-safe power assertions with re-arm (P0).** PowerKeeper now creates assertions via `IOPMAssertionCreateWithProperties` with a 120-second timeout (`kIOPMAssertionTimeoutKey = 120`, `kIOPMAssertionTimeoutActionKey = kIOPMAssertionTimeoutActionRelease`). A 90-second re-arm loop keeps the timeout from reaching zero without recreating IDs unless the kernel reaps the assertion.
18. **Battery safety floor (P1).** Added `PowerSourceMonitor` using `IOPSCopyPowerSourcesInfo` on a coalescing `DispatchSourceTimer` (20s interval, 5s leeway). Assertions pause automatically on battery when charge falls to or below the configurable threshold (default 20%, 0 = disabled), and resume when reconnected to power.
19. **Monotonic continuous awake cap (P1).** Hold duration is tracked using monotonic `ProcessInfo.processInfo.systemUptime`. Reaching the configurable cap (default 4 hours, 0 = disabled) releases assertions and notifies the user without flapping.
20. **Clean release on sleep and termination signals (P1).** `NSWorkspace.willSleepNotification` releases assertion handles prior to sleep and `didWakeNotification` recreates them fresh. `SIGTERM` and `SIGINT` are caught via `DispatchSourceSignal` to run `shutdown()` and clean up IOKit assertions before process exit.
21. **Human-readable localized assertion reasons (P2).** Assertions pass `kIOPMAssertionHumanReadableReasonKey` and `kIOPMAssertionLocalizationBundlePathKey` for localized display in `pmset` and macOS system menus. Dynamic reason updates modify existing assertion properties via `IOPMAssertionSetProperty` without creating redundant assertions.
22. **Hold diagnostics in the menu bar dashboard and settings (P2).** Added live diagnostics displaying system and display assertion IDs, re-arm countdown timer, power source status, and the most recent power lifecycle event.

23. **Agent awareness was too subtle and the count lived only in the dashboard (#15).** The chest badge now carries the status light (green while sessions work, amber while one waits) plus a pip row with one filled dot per active session (a capped `5+` row past that), which stays readable at the 45 pt minimum pet size without covering the face. Working sessions also breathe slightly quicker with a small work bob. Waiting sessions raise a paw on the procedural cat, lean and lift the tail on sprite characters, show a double-stroked `?` glyph and the y/n bubble, and suppress playful moments and roaming until the answer arrives. Everything freezes to a static, readable state under Reduce Motion or with animations disabled, and the light plus count follow the new **Settings -> Power -> AI agent connection** toggle.
24. **The pet could only ever be Kiwi (#14).** Packs gained a format version: format 2 adds `pet.json` and the layer images of a character. The new **Kot-Arbuz** watermelon cat is drawn from `body.png` + `tail.png` derived from the maintainer's master art; the body breathes, the tail wags around its pivot, and every agent detail (light, count, waiting glyph) works identically on it. An invalid or incomplete character pack is skipped instead of rendering a broken pet, and `Scripts/validate-skins.py` validates both formats, the manifest ranges, and the layer canvases.

## Checks run locally and on GitHub

`./Scripts/check-project.sh` completed successfully in the current Linux checkout:

- `bash -n` passed for all `Scripts/*.sh`;
- the 149 English `L10n` source keys match `Localizable.xcstrings`;
- all three bundled manifests passed schema, range, effect, and unique-ID validation;
- hook smoke tests passed with a mocked `open` command, checking start/heartbeat/done, successful and failing wrapped commands, return codes, and rejection of invalid actions/IDs (7 expected URL events);
- `grep -rn '[А-Яа-я]' Sources/` returned no matches;
- **local Swift build was skipped** because this workspace is Linux without Swift/Xcode and the macOS 14 SDK.

GitHub Actions run [37518870521](https://github.com/bestdeejay-design/sweet-no-sleep/actions/runs/37518870521) passed on a macOS 15 runner: portable checks, debug `swift build`, the full `Scripts/check-project.sh` including the 48-step `pet.panelOrigin` movement smoke test, `Scripts/build-app.sh release`, app/resource-bundle assertions, and ad-hoc signature verification. The runner did not launch the full app or interact with its Settings UI; those acceptance checks remain manual.

The validator also accepts a user pack directory or one manifest:

```bash
python3 Scripts/validate-skins.py /path/to/ocean
```

## Mac acceptance checklist

On a Mac, run `./Scripts/check-project.sh`, then `./Scripts/build-app.sh release`, open the generated `.app`, and test:

### Settings and skins

- Open **Settings** from the menu-bar footer, close it with the red close button, then open it again from the footer. Repeat to verify the second and later opens work reliably; visit Focus, Pet, and Power.
- Change duration, size, visibility, always-on-top, animation/Reduce Motion, break interval, display behavior, and launch-at-login settings. Confirm persistence after relaunch.
- Select each bundled skin. Confirm the Settings card, desktop pet, and menu preview agree; relaunch and confirm the choice persisted.
- Install a valid user pack under `~/Library/Application Support/SweetNoSleep/PetSkins/<pack>/skin.json`, refresh, select, and relaunch. Test a user pack that overrides a bundled ID, then remove it and restore the bundled look.
- Confirm a malformed manifest is skipped without hiding other packs or crashing the app.

### Pet panel and behavior

- Adjust size from 90 to 170 pt, drag the pet, and check saved position, transparent hit testing, clicks, and break-bubble buttons.
- Trigger a break reminder; check panel resizing, snooze, dismiss, disabling reminders, and timer restart.
- Check pointer tracking on the desktop and ensure the menu preview does not track the menu window. Toggle animation and system Reduce Motion.
- Enable roaming under **Settings → Pet → Behavior**; check the initial stroll after about 3 seconds and later strolls at about 28-second intervals. Confirm `pet.panelOrigin` changes during movement and after the stroll; do not use log messages alone as proof. Also check drag, hide/show, normal/floating level, Spaces, and multiple displays.

### Power and agent hooks

- Enable and disable manual protection and inspect `pmset -g assertions`: Sweet No Sleep should own exactly one `PreventUserIdleSystemSleep` assertion, plus one display assertion only when enabled. Test the optional display assertion separately.
- Inspect `pmset -g assertions | grep "pid $(pgrep -x SweetNoSleep)"`: verify `Timeout` shows 120s countdown and re-arms at ~90s without creating new assertion IDs.
- Test `kill -9 <pid>` mid-session: verify the kernel reaps the assertion within 120 seconds with no app cleanup.
- Test `kill <pid>` (SIGTERM) mid-session: verify the signal handler releases assertions immediately.
- Test battery floor: on a laptop on battery below threshold (e.g. 20%), verify assertions pause and status reflects battery floor; connect power adapter and verify protection automatically resumes.
- Test continuous awake cap: verify hold releases and notifies when monotonic uptime reaches the cap.
- Open Hold diagnostics in the menu bar dashboard and Settings > Power; confirm live updates for assertion IDs, next re-arm countdown, power source, and last power event with ≤1s staleness.
- Run a safe timed session with normal sleep on completion. Test immediate sleep only in a controlled environment without important work. Confirm a new agent event in the short delay cancels the sleep request.
- Test `./Scripts/agent-session.sh smoke-1 -- <short-command>`, a failed command, manual agent-session stop, bridge disable, and lease expiry without heartbeat. Start with normal sleep, not immediate sleep.
- Test Mac sleep/wake during an active session and confirm assertions release before sleep and restore after wake.
- Click the menu-bar **Settings** button and confirm the Settings scene opens while the app uses accessory activation policy.
- Webhook lifecycle (B-05): enable/disable the loopback bridge several times in a row; confirm port 18290 is released (`lsof -iTCP:18290 -sTCP:LISTEN`). Launch a second instance while the first holds the port and confirm the in-use error. Regenerate the token while a client is mid-request and confirm the old bearer is rejected. Automated contract tests: `python3 Scripts/test-webhook-auth.py`.

## Further development plan

### Priority 0 — Mac validation

- Manually launch the CI-built `.app`, confirm the menu-bar Settings action opens the Settings scene, and run the power, skin, and roaming scenarios above on macOS 14+.
- Record results on Apple Silicon/Intel, single/multiple displays, and across Spaces.
- Compare the live pet against `docs/images/agent-awareness-states.png` and
  `docs/images/agent-awareness-min-size.png`: those images are an offline
  mock-up built from the same drawing constants, not a screen capture.
- Add Swift unit tests for pure model/validation components once a macOS test environment is available.

### Priority 1 — Agent workflow reliability

- Add provider-specific Claude Code, Codex, and IDE hooks with explicit running, waiting-for-approval, completed, and failed events; keep heartbeat/TTL as a safety net.
- Keep assertion failures visible alongside active lease state.
- Decide whether the local URL bridge needs additional controls beyond opt-in; a custom URL scheme is not authentication.

### Priority 2 — Pet and workflow extensibility

- Extend skin packs with independent clips/poses and additional silhouettes while keeping manifests data-only.
- Add selected-skin preview, skipped-pack diagnostics, and a reset-to-bundled action.
- Consider monitor selection, a hotkey, and adaptive power modes after the core loop is stable.

## Audit limits

- AppKit panels, IOKit assertions, and the menu-bar UI were not interactively exercised. The macOS runner built and signed the `.app` but did not launch it. Hook smoke tests use a mocked `open` command and do not prove URL-scheme registration in an installed `.app`.
- The local URL bridge is opt-in but not authenticated; any local process that can open the registered scheme can send events.
- The assertion protects against idle sleep; it cannot override lid closure, user-initiated sleep, critical power conditions, or system policy.
