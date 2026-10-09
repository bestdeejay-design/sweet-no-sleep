import AppKit
import Foundation
import Darwin

@main
struct PanelWanderSmokeTest {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let suiteName = "com.sweetnosleep.panel-wander-smoke"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fail("Could not create isolated test defaults.")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear

        let start = NSPoint(x: 100, y: 100)
        let target = NSPoint(x: 360, y: 280)
        panel.setFrameOrigin(start)
        panel.orderFrontRegardless()

        let animator = PanelOriginAnimator()
        var observedIntermediateOrigin = false
        var finished = false
        animator.animate(
            panel: panel,
            to: target,
            onStep: { origin in
                PetPanelPosition.store(origin, defaults: defaults)
                if origin != start && origin != target {
                    observedIntermediateOrigin = true
                }
            },
            completion: {
                finished = true
            }
        )

        // Allow heavy scheduling slack on loaded macOS runners: the animation
        // itself lasts 4.8 s, but CI boxes routinely stall timers 3-5x.
        let deadline = Date().addingTimeInterval(40)
        while !finished && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        let finalOrigin = panel.frame.origin
        let savedOrigin = PetPanelPosition.restore(defaults: defaults)
        panel.orderOut(nil)
        panel.close()
        defaults.removePersistentDomain(forName: suiteName)

        let frameMoved = isApproximatelyEqual(finalOrigin, target)
        let originPersisted = savedOrigin.map { isApproximatelyEqual($0, target) } ?? false
        guard finished, observedIntermediateOrigin, frameMoved, originPersisted else {
            fail("Panel wander did not move and persist pet.panelOrigin. frame=\(finalOrigin), saved=\(String(describing: savedOrigin)), intermediate=\(observedIntermediateOrigin), finished=\(finished)")
        }

        print("Panel wander smoke test passed: 48 eased frame steps moved pet.panelOrigin to the target.")
    }

    private static func isApproximatelyEqual(_ lhs: NSPoint, _ rhs: NSPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
    }

    private static func fail(_ message: String) -> Never {
        fputs("Panel wander smoke test failed: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
