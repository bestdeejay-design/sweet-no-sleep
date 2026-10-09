import Foundation

/// Headless unit test for the panel geometry shared by the SwiftUI stack and
/// the AppKit panel frame (issue #21 P0). The clipping bug came from the two
/// sides disagreeing about whether a dismissed waiting bubble occupies space;
/// both now call PetPanelLayout, so pinning its truth table pins the fix.
@main
struct PanelLayoutSmokeTest {
    static func main() {
        var failures = 0
        func expect(_ actual: CGFloat, _ expected: CGFloat, _ label: String) {
            guard abs(actual - expected) < 0.001 else {
                print("FAIL \(label): \(actual) != \(expected)")
                failures += 1
                return
            }
            print("ok \(label) = \(actual)")
        }

        let pet: CGFloat = 132
        let side = pet + 48

        // Waiting cue on screen: bubble height and wide-enough width.
        let waiting = PetPanelLayout.contentSize(petSize: pet, showsWaitingBubble: true, isBreakDue: true)
        expect(waiting.height, side + 100, "waiting wins over break reminder")
        expect(waiting.width, max(side, 228), "waiting width")

        // Dismissed waiting cue while the agent still waits: no bubble space.
        // This is the regression: the view used to key off hasWaitingAgent and
        // kept 92pt of bubble inside a panel that had already shrunk.
        let dismissed = PetPanelLayout.contentSize(petSize: pet, showsWaitingBubble: false, isBreakDue: false)
        expect(dismissed.height, side, "dismissed waiting cue occupies no space")
        expect(dismissed.width, side, "dismissed waiting cue width")

        let breakOnly = PetPanelLayout.contentSize(petSize: pet, showsWaitingBubble: false, isBreakDue: true)
        expect(breakOnly.height, side + 96, "break reminder height")

        expect(PetPanelLayout.topInset(showsWaitingBubble: true, isBreakDue: false), 100, "gaze inset matches waiting bubble")
        expect(PetPanelLayout.topInset(showsWaitingBubble: false, isBreakDue: true), 96, "gaze inset matches break bubble")
        expect(PetPanelLayout.topInset(showsWaitingBubble: false, isBreakDue: false), 0, "gaze inset without bubble")

        if failures > 0 {
            print("Panel layout smoke test failed: \(failures) issue(s).")
            exit(1)
        }
        print("Panel layout smoke test passed.")
    }
}
