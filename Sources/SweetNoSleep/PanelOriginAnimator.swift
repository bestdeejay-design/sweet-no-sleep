import AppKit
import Foundation

enum PetPanelPosition {
    static let defaultsKey = "pet.panelOrigin"

    static func store(_ origin: NSPoint, defaults: UserDefaults = .standard) {
        defaults.set([Double(origin.x), Double(origin.y)], forKey: defaultsKey)
    }

    static func restore(defaults: UserDefaults = .standard) -> NSPoint? {
        guard let saved = defaults.array(forKey: defaultsKey) as? [Double], saved.count == 2 else {
            return nil
        }
        return NSPoint(x: CGFloat(saved[0]), y: CGFloat(saved[1]))
    }
}

/// Moves borderless AppKit panels with explicit frame updates. NSAnimationContext
/// does not reliably animate `setFrameOrigin` for non-activating panels.
@MainActor
final class PanelOriginAnimator {
    static let stepCount = 48
    static let duration: TimeInterval = 4.8

    private weak var panel: NSWindow?
    private var timer: Timer?
    private var startOrigin: NSPoint?
    private var targetOrigin: NSPoint?
    private var currentStep = 0
    private var onStep: ((NSPoint) -> Void)?
    private var completion: (() -> Void)?

    func animate(
        panel: NSWindow,
        to target: NSPoint,
        onStep: @escaping (NSPoint) -> Void,
        completion: @escaping () -> Void
    ) {
        cancel()
        self.panel = panel
        startOrigin = panel.frame.origin
        targetOrigin = target
        currentStep = 0
        self.onStep = onStep
        self.completion = completion

        timer = Timer.scheduledTimer(
            withTimeInterval: Self.duration / Double(Self.stepCount),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advance()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        panel = nil
        startOrigin = nil
        targetOrigin = nil
        currentStep = 0
        onStep = nil
        completion = nil
    }

    private func advance() {
        guard let panel, let startOrigin, let targetOrigin else {
            cancel()
            return
        }

        currentStep += 1
        let progress: CGFloat
        if currentStep >= Self.stepCount {
            progress = 1
        } else {
            let normalized = Double(currentStep) / Double(Self.stepCount)
            progress = CGFloat((1 - cos(Double.pi * normalized)) / 2)
        }

        let origin = NSPoint(
            x: startOrigin.x + (targetOrigin.x - startOrigin.x) * progress,
            y: startOrigin.y + (targetOrigin.y - startOrigin.y) * progress
        )
        panel.setFrameOrigin(origin)
        onStep?(origin)

        guard currentStep >= Self.stepCount else { return }
        finish()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        panel = nil
        startOrigin = nil
        targetOrigin = nil
        currentStep = 0
        onStep = nil
        let completion = self.completion
        self.completion = nil
        completion?()
    }
}
