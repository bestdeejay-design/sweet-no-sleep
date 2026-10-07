# Improvement Ideas

A prioritized list of improvements we want in SweetNoSleep, each with a
proposed solution and acceptance criteria written so the work can be picked up
directly. Items are grouped by priority. Nothing here is scheduled until it is
claimed and agreed on.

## Scope guard (applies to every item)

- English only in code, comments, docs, and source strings. New user-facing
  strings go through `Localizable.xcstrings` and `Scripts/localize.sh`.
- Do not touch: the menu bar icon assets, pet skins, media pack, or the
  `Resources/Art` pipeline.
- Existing behavior must not regress: a focus session still holds
  `PreventUserIdleSystemSleep`, the optional display assertion still works,
  and `Scripts/check-project.sh` plus CI stay green.
- No new runtime dependencies. Frameworks allowed: IOKit, AppKit, ServiceManagement, Foundation.
- Every item ships with the Mac acceptance note appended to `docs/CODE_AUDIT.md`.

---

## P0 — fail-safe power assertions

### Idea: assertions that expire on their own

**Problem.** Assertions are currently created with
`IOPMAssertionCreateWithName` and have no expiry. If the app hangs or is
force-quit while macOS keeps the process alive in a bad state, nothing bounds
how long the Mac stays awake. The failure mode of a keep-awake app must be
"the Mac slept too early", never "the Mac never slept".

**Proposed solution.** Create every assertion through
`IOPMAssertionCreateWithProperties` with:

- `kIOPMAssertionTimeoutKey = 120` (seconds)
- `kIOPMAssertionTimeoutActionKey = kIOPMAssertionTimeoutActionRelease`

While a session is active, a refresh loop re-arms the timeout by calling
`IOPMAssertionSetProperty(id, kIOPMAssertionTimeoutKey, 120)` at 75% of the
lifetime (~90 s in), instead of releasing and recreating. Re-arming keeps the
same assertion ID and restarts the countdown, which is cheaper and avoids a
gap where neither the old nor the new assertion is live.

If re-arm fails (the kernel already reaped the ID), treat the assertion as
dead: forget the ID and create a fresh one. If `release()` fails, forget the
handle first and let the kernel timeout reap it — never retry a stale ID
forever.

**Acceptance criteria.**

- [ ] During an active session, `pmset -g assertions | grep -i "sweet no sleep"`
      shows a `Timeout` value that never reaches 0 while the app is alive.
- [ ] `kill -9` the app mid-session → within ~120 s the assertion disappears
      from `pmset -g assertions` with no cleanup code involved.
- [ ] Display and system assertions are tracked independently; a failure
      handling one does not release the other.
- [ ] Hold reason shown in `pmset -g assertions` updates when the reason changes.

---

## P1 — safety limits

### Idea: battery floor

**Problem.** A session on battery can drain the machine flat; the user comes
back to a dead laptop and lost work.

**Proposed solution.** Poll the power source with
`IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList` on a coalescing
`DispatchSourceTimer` (15–30 s, ≥20% leeway), publishing only on change.
While on battery, release all assertions when charge drops below a threshold
(default 20%, configurable in Settings, `0` = disabled). Re-acquire the hold
when plugged back in and the session is still active. Desktops (no internal
battery) never trigger the floor.

**Acceptance criteria.**

- [ ] Unplug below the threshold → assertions release, panel explains the
      reason ("Battery below 20%").
- [ ] Plug back in during the same session → hold resumes automatically.
- [ ] No visible polling cost: timer uses leeway, publishes on change only.

### Idea: hard cap on continuous awake time

**Problem.** A forgotten session in Always On mode keeps the Mac awake
indefinitely.

**Proposed solution.** Track hold duration with a monotonic clock
(`ProcessInfo.systemUptime`) — immune to wall-clock changes, and it pauses
during actual system sleep, which is correct: a sleeping Mac is not being
held. When the cap is reached (default 4 h, configurable), release all
assertions and notify. The cap trips once per hold; it does not re-arm until
the user starts a new session, so it cannot flap.

**Acceptance criteria.**

- [ ] Cap reached → assertions release, notification fired, panel state updates.
- [ ] Moving the system clock forward does not shorten the remaining cap time.
- [ ] Starting a fresh session resets the cap.

### Idea: release on sleep and on termination signals

**Problem.** On `NSWorkspace.willSleepNotification` the assertions stay up
until wake, and SIGTERM/SIGINT bypass `shutdown()` entirely.

**Proposed solution.**

1. Observe `willSleepNotification` and release assertions there; on
   `didWakeNotification` the existing re-acquisition path recreates them
   fresh (IDs may be invalidated across sleep). Never keep an assertion
   "through" a system-initiated sleep — we must not fight the user's own
   sleep command.
2. Install a termination watch: `signal(SIGTERM, SIG_IGN)` first (the default
   disposition would kill the process before the handler runs), then a
   `DispatchSourceSignal` that calls `shutdown()` and exits. Same for SIGINT.

**Acceptance criteria.**

- [ ] Apple menu → Sleep mid-session: assertions gone before sleep completes;
      after wake the session resumes protection automatically.
- [ ] `kill <pid>` (SIGTERM) mid-session: assertions released, `pmset` clean.
- [ ] Normal quit and app update flows unchanged.

---

## P2 — observability and polish

### Idea: human-readable assertion reason

**Problem.** The assertion reason is a fixed English string; `pmset -g
assertions` and the Battery menu show it raw.

**Proposed solution.** Pass `kIOPMAssertionHumanReadableReasonKey` with the
user-facing reason and `kIOPMAssertionLocalizationBundlePathKey` pointing at
the app bundle, so macOS localizes the reason in system UI. Include the
session label (e.g. "Sweet No Sleep — focus session 'Deep work'").

**Acceptance criteria.**

- [ ] `pmset -g assertions` shows the localized, per-session reason.
- [ ] Changing the reason mid-hold updates the existing assertion without
      creating a second one.

### Idea: hold diagnostics in the panel

**Problem.** When the Mac sleeps anyway (or does not sleep), the user has no
in-app way to see what the app thinks it is doing.

**Proposed solution.** A collapsible "Diagnostics" row in the panel showing:
assertion state (system/display), assertion ID, seconds until next re-arm,
battery state, and the last power-related event. Plus a one-line hint in
README: `pmset -g assertions | grep "pid $(pgrep -x SweetNoSleep)"` so users
can verify independently of the app.

**Acceptance criteria.**

- [ ] Diagnostics reflect live state with ≤1 s staleness.
- [ ] Hidden by default; no new permissions or strings beyond the localization
      catalog.

---

## P3 — bigger bets (design discussion required before coding)

These are deliberately not specified to the same depth. Claim one, and the
first step is a short design note in a PR before any implementation.

- **Closed-lid hold.** Working with the lid shut requires the kernel
  `SleepDisabled` flag, which needs root and outlives the process — a
  privileged helper plus hard caps (max duration, thermal release) would be
  mandatory. Big security surface; only worth it if there is real demand.
- **Night dimming.** When the display assertion holds the screen on overnight,
  dim it on a schedule and restore on user input — saves the panel and the
  room. Needs careful input detection (pointer travel, not raw events).
- **Agent activity detection.** Auto-start a hold when a coding agent
  (Claude Code, Codex, …) is working, release when it stops — transcript
  watching with FSEvents plus optional local hooks. This is a product-level
  feature; needs its own PRD before code.
- **Local webhook.** A loopback-only endpoint (`127.0.0.1`, bearer token)
  so any tool can start/stop a session with one `curl`. Pairs with the
  previous item as the "exact" signal source.

---

## Priority summary

| Priority | Item | Size |
|---|---|---|
| P0 | Self-expiring assertions with re-arm | S–M |
| P1 | Battery floor | S |
| P1 | Hard cap on continuous awake time | S |
| P1 | Release on sleep + SIGTERM/SIGINT | S |
| P2 | Human-readable localized assertion reason | S |
| P2 | Hold diagnostics in the panel | M |
| P3 | Closed-lid hold / night dimming / agent detection / webhook | XL (design first) |
