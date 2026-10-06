# Product research and design specification

**Project:** Sweet No Sleep — Kiwi Cat
**Platform:** macOS 14+, SwiftUI + AppKit
**Goal:** a friendly desktop companion with clear controls for when the Mac should stay awake.

This is technical and UX research, not a guarantee that every IDE or agent will keep running. The pet can manage system idle-sleep assertions; knowing whether a third-party agent is active requires an explicit integration.

---

## 1. Product problem

The product has two related but distinct roles:

1. **The desktop character** should feel alive, recognizable, and responsive without interfering with typing or demanding constant attention.
2. **Awake-state control** should have an explicit start, a clear reason, a timer, visible status, and reliable assertion cleanup. Indefinite sleep prevention must not be a hidden side effect of an animation.

The key scenario is a long test or agent session:

```text
user starts a focus session
→ Kiwi shows that it is on duty and holds an idle-sleep assertion
→ the display may turn off separately, if allowed
→ the assertion is released when the timer ends
→ macOS resumes its normal sleep behavior, unless the user explicitly chose immediate sleep
```

An agent can start or renew a session through explicit local events (`start` and `heartbeat`) and report `done` or `failed`. Without such an integration, the app does not infer agent state from open processes or windows.

---

## 2. macOS desktop layer

### Recommended primitive

A **transparent, borderless `NSPanel` hosted by `NSHostingView`** is a good fit for the character instead of a conventional main window:

- `NSPanel` is intended for floating auxiliary windows;
- `.nonactivatingPanel` helps avoid stealing focus from an IDE;
- a transparent background and SwiftUI hosting provide a seamless layer;
- `.canJoinAllSpaces` and `.fullScreenAuxiliary` allow the pet to remain nearby across Spaces and fullscreen contexts;
- `.floating` is a user setting because it can cover code or dialogs.

This aligns with the macOS HIG description of panels as floating auxiliary information. The window is intentionally not presented as a wallpaper layer: that is less supported, limits interaction, and depends on WindowServer internals. A controllable panel is more reliable for daily use.

### Current implementation

Kiwi uses a transparent, non-activating `NSPanel`. It does not use Screen Recording, the Accessibility API, or read other windows' titles. Dragging only moves its own window. Users can hide the pet or disable **Keep above other windows**.

### Limits

- `.floating` can still cover a control, so roaming is off by default and the pet can be hidden from the menu.
- Fullscreen Spaces and multiple displays have distinct geometry. The panel joins all Spaces and roaming is limited to the visible area of its current display; monitor selection and window avoidance remain future work.
- A “desktop layer” is not a system wallpaper layer; it is a normal, managed window above the desktop environment.

---

## 3. Character animation

### Principles for a pleasant character

1. **Secondary motion, not constant activity.** Subtle breathing, occasional blinking, a delayed tail sway, and slight head movement keep the silhouette readable.
2. **A clear state set.** `idle → working → celebrating / resting`, plus `dragging` and `walking`. Every action has a beginning and end; the pet should not get stuck in a reaction.
3. **Visible reasons for movement.** A click earns a smile/sparkle; awake mode gets a working pose and glow; a completed timer gets a brief celebration; dragging gets a stretched pose and steps.
4. **A lower update rate than typical interface animation.** Canvas updates at up to about 24 fps normally. With Reduce Motion, body movement pauses while a light update can remain for pointer gaze. Hidden pets stop updating.
5. **No required audio or flashing.** Bright effects are brief and rare; there is no sound by default.
6. **Silhouette and palette first.** Kiwi has warm fur, distinct ears, and a green fruit badge; reactions and effects are secondary.

### Current visual language

- Three bundled JSON skins: `Kiwi`, `Moonlight`, and `Strawberry`; user color packs load from Application Support.
- The pet is drawn with vector `Path` shapes on `Canvas`, without external artwork dependencies.
- Breathing, pointer-following eyes, occasional blinking, and tail movement.
- Short random dances, stretches, and curious looks only during an active awake session; there is an independent toggle.
- A configurable reminder suggests a short eye break during an active session; it can be snoozed or dismissed and does not block work.
- Roaming is optional, starts about 3 seconds after enable, and then runs about every 28 seconds. It respects system Reduce Motion and the animation toggle.

### When to add Rive, Lottie, or sprites

Not yet. For three palettes and a handful of poses, procedural SwiftUI Canvas is simpler to compile, scale, and extend. If the project needs authored cycles such as legged walking, side-sleeping, or articulated costumes, a rig/clip format such as Rive or a custom sprite sheet may be appropriate. Keep static `PetDefinition` data and the animation runtime separate from system power logic.

---

## 4. Settings and information architecture

### Two levels of control

- **Menu-bar dashboard:** daily status, manual switch, duration, Start Focus, countdown, End, show/hide, and Settings.
- **Settings window:** less frequent choices in Focus, Pet, and Power sections.

This keeps the menu short and avoids turning the pet into a miniature system-settings app.

### What should always be clear

- whether the Mac is currently held awake;
- whether the session is manual or timed;
- how much time remains;
- what happens at the end;
- whether the display is also held on;
- how to stop a session immediately.

Immediate sleep is not the default. The user selects that policy and confirms each specific focus session. The softer option releases the app's assertion and lets macOS use its configured idle timeout.

### Accessibility and respect for the workflow

- System Reduce Motion, accessible status labels, and VoiceOver labels.
- A transparent character rather than a large permanent background.
- Roaming is off by default and can be stopped by disabling animations or enabling Reduce Motion.
- Independent controls for size, visibility, and window level.
- No system sounds or push notifications; the optional break prompt is shown in the pet panel.

---

## 5. Power management: behavior and limits

### Current implementation

The app takes a temporary, named `PreventUserIdleSystemSleep` assertion only after an explicit user action. Apple describes it as protection against automatic sleep caused by inactivity; it does not override every reason the Mac may sleep. A separate `NoDisplaySleep` assertion is available if the user also wants the display to stay on. For the main use case, the display assertion is normally unnecessary: the screen can turn off while the system remains awake.

`ProcessInfo.beginActivity(.userInitiated, reason:)` signals that the app is accompanying work explicitly requested by the user, and its token is held until completion. The IOKit assertion provides the explicit power-management contract and a reason visible in `pmset -g assertions`. Assertion IDs are recreated after wake. Assertions and the activity token are released on stop, session completion, and app termination.

### What an assertion cannot guarantee

This is not an unbreakable lock:

- it protects against **idle system sleep**, not sleep requested by the user;
- closing a MacBook lid, critical battery, forced shutdown/sleep, and system policy take precedence;
- it does not guarantee network access, authentication, a third-party agent process, or bypass the agent's own timeouts;
- it does not make “IDE is open” equivalent to “agent is working”;
- display sleep prevention consumes more power, so it is off by default.

### Detecting when an agent has finished

The presence of an application is not a reliable signal: an IDE can be open without an agent, and an agent can run in a shell, remote environment, or child process. Global window/command-line scanning would be brittle and could require unnecessary permissions or produce false positives.

The current implementation includes a minimal **opt-in local URL bridge**: `sweetnosleep://agent/start|heartbeat|done|failed?session=<id>`. `Scripts/agent-event.sh` sends a single event; `Scripts/agent-session.sh <id> -- <command> ...` wraps a command with start/end events and a heartbeat every minute. A heartbeat renews a 180-second lease; multiple session IDs can be active. The bridge is off by default, events never cause immediate sleep, and a missing heartbeat expires a stale lease. This is not an authenticated inter-process protocol: any local process can open the registered URL scheme, so enable the bridge only for trusted hooks.

The robust direction is **provider adapters with explicit lifecycle events**:

```text
agent.started(sessionID, expectedDuration?)
agent.heartbeat(sessionID, state: running | waiting | tests)
agent.waitingForApproval(sessionID)
agent.completed(sessionID, result)
agent.failed(sessionID, reason)
```

A session should have a TTL/heartbeat. If an adapter disappears, the user should see stale state and be able to stop protection. Completing one agent must not allow sleep while another is working. Until provider adapters exist, manual start and timed sessions are the honest, predictable behavior.

---

## 6. Recommended roadmap

### Next: small, useful extensions

1. **Provider adapters:** connect Claude Code hooks and Codex/IDE callbacks to the existing URL bridge; the CLI already covers the general start/heartbeat/done/failed flow.
2. **Multiple concurrent jobs:** keep a lease registry by `sessionID`; the Mac stays awake while any lease remains active.
3. **Waiting for approval:** use a different tail/badge, a quiet status, and an explicit “agent is waiting for you” state without reading other windows.
4. **AC-power policy:** optionally prevent or stop assertions when switching to battery.
5. **Grace period:** after `done`, optionally wait 1–10 minutes before returning to normal sleep; keep immediate sleep as a rare opt-in.
6. **Richer skin packs:** add licensed art, additional silhouettes, and independent clips; the current JSON covers palette, basic motion profile, and one built-in effect for a single character.
7. **New reactions:** distinguish approval requests, completed tests, and breaks while keeping effects rare and switchable.
8. **Desktop-layer controls:** select a display, avoid fullscreen apps, and add a hotkey for pausing/hiding.
9. **Diagnostics:** expose the last assertion state, why it ended, and a copyable troubleshooting report.

### Not recommended yet

- capturing the screen or reading window content to infer agent activity;
- keeping the Mac awake indefinitely by default;
- immediate sleep after any task without a trusted completion signal;
- bright particles, sounds, or fast motion without controls;
- default-on roaming that can cover work.

---

## 7. References

1. Apple, **Prioritize Work at the App Level** — user-initiated work, `NSProcessInfo` activities, and sleep assertions: [developer.apple.com](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/Power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html).
2. Apple, **IOPMAssertionTypes** — `PreventUserIdleSystemSleep` and `NoDisplaySleep`: [assertion types](https://developer.apple.com/documentation/iokit/iopmlib_h/iopmassertiontypes), [idle-sleep assertion](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep).
3. Apple, **IOPMLib** — power-management APIs including assertions and system sleep requests: [developer.apple.com](https://developer.apple.com/documentation/iokit/iopmlib_h).
4. Apple, **NSWorkspace willSleep / didWake notifications** — sleep and wake lifecycle: [willSleep](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification), [didWake](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification).
5. Apple, **macOS Human Interface Guidelines — Panels** — floating auxiliary panels: [developer.apple.com](https://developer.apple.com/design/human-interface-guidelines/macos/windows-and-views/panels).
6. Apple, **SwiftUI TimelineSchedule.animation** — a pausable timeline with a configurable minimum interval: [developer.apple.com](https://developer.apple.com/documentation/swiftui/timelineschedule/animation(minimuminterval:paused:)).
7. Apple, **SMAppService** — login-item registration and user approval: [mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp?language=objc), [register](https://developer.apple.com/documentation/servicemanagement/smappservice/register()).
8. Apple, **NSWorkspace accessibilityDisplayShouldReduceMotion** — macOS Reduce Motion state: [developer.apple.com](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion).
9. Cindori, **Make a floating panel in SwiftUI for macOS** — practical `NSPanel` + `NSHostingView` example: [cindori.com](https://cindori.com/developer/floating-panel).

---

## 8. Pre-release verification

- Inspect assertions in `pmset -g assertions` with awake mode on and off.
- Wait for a short timed session to end and confirm the assertion is released.
- Test normal sleep and immediate sleep separately, first on a test setup without critical work.
- Manually check lid closure, wake, power-source changes, and multiple Spaces.
- Check Reduce Motion, VoiceOver, small/large pet size, and hiding the panel.
- Test roaming on one and multiple displays; confirm the pet stays within the visible frame and is not hidden behind the Dock.
