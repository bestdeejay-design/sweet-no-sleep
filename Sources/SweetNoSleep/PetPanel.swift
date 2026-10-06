import AppKit
import SwiftUI

// Transparent floating panel that hosts Kiwi, the desktop pet.
// Borderless and non-activating so it never steals focus from other apps.
final class PetPanel: NSPanel {

    // Creates the panel wrapping an already-built content view.
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hasShadow = false
        ignoresMouseEvents = false
        self.contentView = contentView
    }
}

// Helper that attaches an arbitrary SwiftUI view to a PetPanel
// through NSHostingView, so the app never touches AppKit directly.
enum PetPanelHosting {

    // Builds a panel hosting the given SwiftUI content at the given size.
    static func makePanel<Content: View>(
        for content: Content,
        size: NSSize = NSSize(width: 160, height: 160)
    ) -> PetPanel {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)
        let panel = PetPanel(contentView: hostingView)
        panel.setContentSize(size)
        return panel
    }

    // Replaces the hosted SwiftUI content of an existing panel.
    static func setContent<Content: View>(_ content: Content, on panel: PetPanel) {
        if let hostingView = panel.contentView as? NSHostingView<Content> {
            hostingView.rootView = content
        } else {
            panel.contentView = NSHostingView(rootView: content)
        }
    }
}
