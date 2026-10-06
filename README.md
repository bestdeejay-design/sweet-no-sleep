# SweetNoSleep

MenuBar desktop pet **Kiwi** that keeps your Mac awake.

Stage 1 (circle): transparent floating `NSPanel`, breathing/blinking Canvas circle, drag support, `PowerKeeper` via `ProcessInfo.beginActivity` + `IOPMAssertion`.

## Run

```bash
swift run --package-path ~/Projects/sweet-no-sleep
# or open Package.swift in Xcode and Run
```

Toggle `Keep Awake` in the MenuBar (`circle.fill` icon). Verify with:

```bash
pmset -g assertions | grep -i kiwi
```

## Structure

- `Sources/SweetNoSleep/SweetNoSleepApp.swift` — MenuBarExtra + AppDelegate pet window
- `Sources/SweetNoSleep/PetPanel.swift` — borderless nonactivating panel
- `Sources/SweetNoSleep/KiwiCircleView.swift` — Canvas breathing/blink/cursor
- `Sources/SweetNoSleep/KiwiBrain.swift` — PetState idle/dragged/sleeping
- `Sources/SweetNoSleep/PowerKeeper.swift` — display + system assertions
- `Sources/SweetNoSleep/SettingsView.swift` — login item, size S/M/L
- `Resources/` — reserved for `kiwi-cat` sprites (stage 2)

All code, docs and settings are English-only. Localization is generated, never hand-edited (see below).

## Localization

Source of truth: `Sources/SweetNoSleep/Localizable.xcstrings` (`en` only).
`Scripts/localize.sh` auto-fills other locales via DeepL/Crowdin on tag. Do not edit translations by hand.

## Roadmap

1. Circle (done) — panel, breathing, PowerKeeper
2. Kiwi look — ears/tail/kiwi-heart from `ksu/portfolio/stickers/kiwi-cat.jpg`
3. Reactions — poke/drag states via `KiwiBrain`
4. Assistant — battery/time/idle events
