import AppKit
import Combine
import SwiftUI

/// Clear, non-activating desktop layer for the animated companion.
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentView: NSView, size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .utilityWindow
        self.contentView = contentView
    }
}

/// Passes mouse input through the transparent part of the pet's square panel.
/// The hand-drawn cat occupies only a small part of the hosting view; rejecting
/// empty corners prevents the invisible window from covering code underneath.
final class PetLayerHitTestView: NSView {
    var petSize: CGFloat = 132
    var showsBreakReminder = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsPet(at: point) else { return nil }
        return super.hitTest(point)
    }

    private func containsPet(at point: NSPoint) -> Bool {
        let xInPanel = point.x
        let yInPanel = bounds.height - point.y // Convert AppKit's bottom-left origin to SwiftUI's top-left origin.
        let petSide = petSize + 48
        let petInsetX = (bounds.width - petSide) / 2
        let petInsetY = showsBreakReminder ? PetBreakReminderBubble.height : 0

        if showsBreakReminder,
           yInPanel <= PetBreakReminderBubble.height,
           abs(xInPanel - bounds.midX) <= PetBreakReminderBubble.width / 2 {
            return true
        }

        let x = xInPanel - petInsetX
        let y = yInPanel - petInsetY
        let radius = petSide * 0.335
        let center = CGPoint(x: petSide * 0.5, y: petSide * 0.55)
        let head = CGPoint(x: center.x, y: center.y - radius * 0.23)

        let faceDX = (x - head.x) / (radius * 0.88)
        let faceDY = (y - head.y) / (radius * 0.82)
        if faceDX * faceDX + faceDY * faceDY <= 1 { return true }

        let bodyDX = (x - center.x) / (radius * 0.66)
        let bodyDY = (y - (center.y + radius * 0.45)) / (radius * 0.63)
        if bodyDX * bodyDX + bodyDY * bodyDY <= 1 { return true }

        // Approximate the two pointed ears and tapered tail with tolerant hit areas.
        let leftEar = triangleContains(
            CGPoint(x: x, y: y),
            a: CGPoint(x: head.x - radius * 0.84, y: head.y - radius * 1.02),
            b: CGPoint(x: head.x - radius * 0.88, y: head.y - radius * 0.33),
            c: CGPoint(x: head.x - radius * 0.32, y: head.y - radius * 0.69)
        )
        let rightEar = triangleContains(
            CGPoint(x: x, y: y),
            a: CGPoint(x: head.x + radius * 0.84, y: head.y - radius * 1.02),
            b: CGPoint(x: head.x + radius * 0.88, y: head.y - radius * 0.33),
            c: CGPoint(x: head.x + radius * 0.32, y: head.y - radius * 0.69)
        )
        if leftEar || rightEar { return true }

        let tailStart = CGPoint(x: center.x + radius * 0.52, y: center.y + radius * 0.46)
        let tailEnd = CGPoint(x: center.x + radius * 1.24, y: center.y + radius * 0.22)
        return distance(from: CGPoint(x: x, y: y), toSegmentFrom: tailStart, to: tailEnd) <= radius * 0.18
    }

    private func triangleContains(_ point: CGPoint, a: CGPoint, b: CGPoint, c: CGPoint) -> Bool {
        let area = abs((a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)) / 2)
        guard area > 0 else { return false }
        let area1 = abs((point.x * (b.y - c.y) + b.x * (c.y - point.y) + c.x * (point.y - b.y)) / 2)
        let area2 = abs((a.x * (point.y - c.y) + point.x * (c.y - a.y) + c.x * (a.y - point.y)) / 2)
        let area3 = abs((a.x * (b.y - point.y) + b.x * (point.y - a.y) + point.x * (a.y - b.y)) / 2)
        return abs(area - area1 - area2 - area3) < 1
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return CGFloat(hypot(Double(point.x - start.x), Double(point.y - start.y)))
        }
        let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return CGFloat(hypot(Double(point.x - projection.x), Double(point.y - projection.y)))
    }
}

/// Owns the desktop panel and keeps its location, size and optional wandering in sync.
@MainActor
final class PetPanelController {
    private let model: SweetNoSleepModel
    private var panel: PetPanel?
    private var dragOrigin: NSPoint?
    private var wanderTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let positionKey = "pet.panelOrigin"

    init(model: SweetNoSleepModel) {
        self.model = model
        model.$petSize.dropFirst().sink { [weak self] size in
            self?.updateSize(CGFloat(size))
        }.store(in: &cancellables)
        model.$isBreakDue.dropFirst().sink { [weak self] isDue in
            guard let self else { return }
            // @Published emits from willSet, so use the emitted value instead of
            // re-reading model.isBreakDue before Swift has assigned it.
            self.updateSize(CGFloat(self.model.petSize), showsBreakReminder: isDue)
        }.store(in: &cancellables)
        model.$alwaysOnTop.dropFirst().sink { [weak self] isPinned in
            self?.updateLevel(isPinned: isPinned)
        }.store(in: &cancellables)
        model.$roamingEnabled.dropFirst().sink { [weak self] enabled in
            self?.setRoamingEnabled(enabled)
        }.store(in: &cancellables)
    }

    func show() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            setRoamingEnabled(model.roamingEnabled)
            return
        }

        let size = panelSize(for: CGFloat(model.petSize), showsBreakReminder: model.isBreakDue)
        let rootView = PetDesktopView(
            model: model,
            onDragChanged: { [weak self] translation in self?.movePanel(by: translation) },
            onDragEnded: { [weak self] in self?.finishDragging() }
        )
        let layerView = PetLayerHitTestView(frame: NSRect(origin: .zero, size: size))
        layerView.petSize = CGFloat(model.petSize)
        layerView.showsBreakReminder = model.isBreakDue
        layerView.autoresizingMask = [.width, .height]
        layerView.wantsLayer = true
        layerView.layer?.backgroundColor = NSColor.clear.cgColor
        let hostingView = NSHostingView(rootView: rootView.background(Color.clear))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        layerView.addSubview(hostingView)

        let newPanel = PetPanel(contentView: layerView, size: size)
        newPanel.isFloatingPanel = model.alwaysOnTop
        newPanel.level = model.alwaysOnTop ? .floating : .normal
        newPanel.setFrameOrigin(restoredOrigin(for: size))
        panel = newPanel
        newPanel.orderFrontRegardless()
        setRoamingEnabled(model.roamingEnabled)
    }

    func hide() {
        wanderTimer?.invalidate()
        wanderTimer = nil
        model.endWandering()
        panel?.orderOut(nil)
    }

    func close() {
        wanderTimer?.invalidate()
        wanderTimer = nil
        panel?.orderOut(nil)
        panel = nil
        cancellables.removeAll()
    }

    private func movePanel(by translation: CGSize) {
        guard let panel else { return }
        if dragOrigin == nil { dragOrigin = panel.frame.origin }
        guard let dragOrigin else { return }
        panel.setFrameOrigin(NSPoint(
            x: dragOrigin.x + translation.width,
            y: dragOrigin.y - translation.height
        ))
    }

    private func finishDragging() {
        guard let panel else { return }
        dragOrigin = nil
        UserDefaults.standard.set(
            [Double(panel.frame.origin.x), Double(panel.frame.origin.y)],
            forKey: positionKey
        )
    }

    private func updateSize(_ petSize: CGFloat, showsBreakReminder override: Bool? = nil) {
        guard let panel else { return }
        let showsReminder = override ?? model.isBreakDue
        let size = panelSize(for: petSize, showsBreakReminder: showsReminder)
        let previousFrame = panel.frame
        let visibleFrame = (NSScreen.screens.first(where: { $0.frame.intersects(previousFrame) }) ?? NSScreen.main)?.visibleFrame
        var origin = NSPoint(x: previousFrame.midX - size.width / 2, y: previousFrame.minY)
        if let visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), max(visibleFrame.maxX - size.width, visibleFrame.minX))
            origin.y = min(max(origin.y, visibleFrame.minY), max(visibleFrame.maxY - size.height, visibleFrame.minY))
        }
        panel.setFrame(
            NSRect(origin: origin, size: size),
            display: true
        )
        if let layerView = panel.contentView as? PetLayerHitTestView {
            layerView.petSize = petSize
            layerView.showsBreakReminder = showsReminder
            layerView.frame = NSRect(origin: .zero, size: size)
        }
    }

    private func updateLevel(isPinned: Bool) {
        guard let panel else { return }
        panel.isFloatingPanel = isPinned
        panel.level = isPinned ? .floating : .normal
    }

    private func panelSize(for petSize: CGFloat, showsBreakReminder: Bool) -> NSSize {
        let petSide = petSize + 48
        let width = showsBreakReminder ? max(petSide, PetBreakReminderBubble.width) : petSide
        let height = petSide + (showsBreakReminder ? PetBreakReminderBubble.height : 0)
        return NSSize(width: width, height: height)
    }

    private func restoredOrigin(for size: NSSize) -> NSPoint {
        if let saved = UserDefaults.standard.array(forKey: positionKey) as? [Double], saved.count == 2 {
            let origin = NSPoint(x: CGFloat(saved[0]), y: CGFloat(saved[1]))
            let savedFrame = NSRect(origin: origin, size: size)
            if let screen = NSScreen.screens.first(where: { $0.frame.intersects(savedFrame) }) {
                let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
                return NSPoint(
                    x: min(max(origin.x, visible.minX), max(visible.maxX - size.width, visible.minX)),
                    y: min(max(origin.y, visible.minY), max(visible.maxY - size.height, visible.minY))
                )
            }
        }

        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visibleFrame.maxX - size.width - 34, y: visibleFrame.minY + 28)
    }

    // MARK: Gentle wandering

    private func setRoamingEnabled(_ enabled: Bool) {
        wanderTimer?.invalidate()
        wanderTimer = nil
        model.endWandering()
        guard enabled, model.isPetVisible, panel?.isVisible == true else { return }
        scheduleInitialWander()
    }

    private func scheduleInitialWander() {
        wanderTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.wanderTimer = nil
            self.wanderOnce()
            self.scheduleRepeatingWander()
        }
    }

    private func scheduleRepeatingWander() {
        guard model.roamingEnabled, model.isPetVisible, panel?.isVisible == true else { return }
        wanderTimer = Timer.scheduledTimer(withTimeInterval: 28, repeats: true) { [weak self] _ in
            self?.wanderOnce()
        }
    }

    private func wanderOnce() {
        guard let panel,
              panel.isVisible,
              model.roamingEnabled,
              model.animationsEnabled,
              !model.isBreakDue,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              model.mood != .dragging
        else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) ?? NSScreen.main else { return }

        var safeFrame = screen.visibleFrame.insetBy(dx: 18, dy: 18)
        safeFrame.size.width = max(safeFrame.width - panel.frame.width, 1)
        safeFrame.size.height = max(safeFrame.height - panel.frame.height, 1)
        let target = NSPoint(
            x: CGFloat.random(in: safeFrame.minX...safeFrame.maxX),
            y: CGFloat.random(in: safeFrame.minY...safeFrame.maxY)
        )

        guard model.beginWandering() else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 4.8
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(target)
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.model.endWandering()
                self.finishDragging()
            }
        }
    }
}
