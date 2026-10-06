# Sweet No Sleep code audit

Audit date: October 6, 2026. Reviewed the application source, settings persistence, skin library, pet renderer, floating panel, power lifecycle, local bridge and shell hooks, app packaging, JSON manifests, and project documentation.

## Summary

Several cross-feature defects were found and fixed. The core flows remain: manual awake mode, timed focus sessions, agent leases with heartbeat/TTL, user skin packs, the transparent pet panel, and configurable behavior.

The current environment is Linux and does not provide Swift/Xcode or the macOS SDK. A native build and AppKit/SwiftUI runtime behavior therefore cannot be confirmed here. The Mac verification checklist below is still required.

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

## Checks run in the repository environment

`./Scripts/check-project.sh` completed successfully in the current Linux checkout:

- `bash -n` passed for all `Scripts/*.sh`;
- the 149 English `L10n` source keys match `Localizable.xcstrings`;
- all three bundled manifests passed schema, range, effect, and unique-ID validation;
- hook smoke tests passed with a mocked `open` command, checking start/heartbeat/done, successful and failing wrapped commands, return codes, and rejection of invalid actions/IDs (7 expected URL events);
- `grep -rn '[А-Яа-я]' Sources/` returned no matches;
- **Swift build was skipped** because this environment is Linux without Swift/Xcode and the macOS 14 SDK.

A macOS GitHub Actions workflow is configured to run the project check, release app packaging, bundle/resource assertions, and ad-hoc signature verification. Its result, native build, and GUI acceptance remain pending a macOS runner.

The validator also accepts a user pack directory or one manifest:

```bash
python3 Scripts/validate-skins.py /path/to/ocean
```

## Mac acceptance checklist

On a Mac, run `./Scripts/check-project.sh`, then `./Scripts/build-app.sh`, open the generated `.app`, and test:

### Settings and skins

- Open **Settings** from the menu-bar footer and visit Focus, Pet, and Power.
- Change duration, size, visibility, always-on-top, animation/Reduce Motion, break interval, display behavior, and launch-at-login settings. Confirm persistence after relaunch.
- Select each bundled skin. Confirm the Settings card, desktop pet, and menu preview agree; relaunch and confirm the choice persisted.
- Install a valid user pack under `~/Library/Application Support/SweetNoSleep/PetSkins/<pack>/skin.json`, refresh, select, and relaunch. Test a user pack that overrides a bundled ID, then remove it and restore the bundled look.
- Confirm a malformed manifest is skipped without hiding other packs or crashing the app.

### Pet panel and behavior

- Adjust size from 90 to 170 pt, drag the pet, and check saved position, transparent hit testing, clicks, and break-bubble buttons.
- Trigger a break reminder; check panel resizing, snooze, dismiss, disabling reminders, and timer restart.
- Check pointer tracking on the desktop and ensure the menu preview does not track the menu window. Toggle animation and system Reduce Motion.
- Enable roaming under **Settings → Pet → Behavior**; check the initial stroll after about 3 seconds and later strolls at about 28-second intervals. Also check drag, hide/show, normal/floating level, Spaces, and multiple displays.

### Power and agent hooks

- Enable and disable manual protection and inspect `pmset -g assertions` for `PreventUserIdleSystemSleep`. Test the optional display assertion separately.
- Run a safe timed session with normal sleep on completion. Test immediate sleep only in a controlled environment without important work. Confirm a new agent event in the short delay cancels the sleep request.
- Test `./Scripts/agent-session.sh smoke-1 -- <short-command>`, a failed command, manual agent-session stop, bridge disable, and lease expiry without heartbeat. Start with normal sleep, not immediate sleep.
- Test Mac sleep/wake during an active session and confirm a warning appears if macOS cannot restore the optional display assertion.
- Click the menu-bar **Settings** button and confirm the Settings scene opens while the app uses accessory activation policy.

## Further development plan

### Priority 0 — Mac validation

- Run Swift build, app bundle assembly, and the acceptance scenarios above on macOS 14+.
- Record results on Apple Silicon/Intel, single/multiple displays, and across Spaces.
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

- AppKit panels, IOKit assertions, and the menu-bar UI were not run in this Linux environment. Hook smoke tests use a mocked `open` command and do not prove URL-scheme registration in an installed `.app`.
- The local URL bridge is opt-in but not authenticated; any local process that can open the registered scheme can send events.
- The assertion protects against idle sleep; it cannot override lid closure, user-initiated sleep, critical power conditions, or system policy.
