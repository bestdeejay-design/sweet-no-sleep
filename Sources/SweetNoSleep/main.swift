import Foundation

/// Entry point of the menu-bar app.
///
/// The hooks before it are headless reports that must run with no window server
/// and no AppKit state: the localization self-check (`Bundle.module`), the pack
/// root report (`--pack-roots`) and the debug mood list (`--debug-moods`). Each
/// exits. Everything else is the normal SwiftUI lifecycle.
if let status = LocalizationSelfCheck.runIfRequested() {
    exit(status)
}
// `--pack-roots` reports which pack folders this process resolves, then exits.
if let status = PackRootSelfCheck.runIfRequested() {
    exit(status)
}
// `--debug-moods` prints the ids `sweetnosleep://debug/mood` accepts, then exits.
if let status = DebugInstruments.runIfRequested() {
    exit(status)
}

SweetNoSleepApp.main()
