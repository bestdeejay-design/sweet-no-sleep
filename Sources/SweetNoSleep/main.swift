import Foundation

/// Entry point of the menu-bar app.
///
/// The one hook before it is the localization self-check, which must run with no
/// window server and no AppKit state: it resolves catalog strings through
/// `Bundle.module` and exits. Everything else is the normal SwiftUI lifecycle.
if let status = LocalizationSelfCheck.runIfRequested() {
    exit(status)
}

SweetNoSleepApp.main()
