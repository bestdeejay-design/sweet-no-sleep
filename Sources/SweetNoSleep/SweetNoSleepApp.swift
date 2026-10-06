import AppKit
import SwiftUI

// Entry point of SweetNoSleep, the Kiwi desktop pet that keeps the Mac awake.
@main
struct SweetNoSleepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var brain = KiwiBrain()
    @StateObject private var keeper = PowerKeeper()

    init() {}

    var body: some Scene {
        MenuBarExtra {
            Toggle("Keep Awake", isOn: Binding(
                get: { brain.isAwake },
                set: { newValue in
                    brain.isAwake = newValue
                    if newValue {
                        keeper.keepAwake(reason: "Kiwi is keeping the Mac awake")
                    } else {
                        keeper.letSleep()
                    }
                }
            ))
            Divider()
            Button("Show Kiwi") { appDelegate.showPet(with: brain) }
            SettingsLink { Text("Settings...") }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } label: {
            Label("Kiwi", systemImage: "circle.fill")
        }
        Settings { SettingsView() }
    }
}

// AppDelegate owns the floating PetPanel so it appears on launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PetPanel?
    private weak var brain: KiwiBrain?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Panel needs the SwiftUI brain; it is injected on first menu render.
        // Fallback: show with a temporary brain so Kiwi is visible immediately.
        DispatchQueue.main.async { [weak self] in
            self?.showPet(with: self?.brain ?? KiwiBrain())
        }
    }

    func showPet(with brain: KiwiBrain) {
        self.brain = brain
        let view = KiwiCircleView(brain: brain)
        if let existing = panel {
            PetPanelHosting.setContent(view, on: existing)
        } else {
            let newPanel = PetPanelHosting.makePanel(for: view, size: NSSize(width: 160, height: 160))
            newPanel.center()
            // Bottom-right above Dock by default.
            if let screen = NSScreen.main?.visibleFrame {
                newPanel.setFrameOrigin(NSPoint(x: screen.maxX - 200, y: screen.minY + 60))
            }
            panel = newPanel
        }
        panel?.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel?.orderOut(nil)
    }
}
