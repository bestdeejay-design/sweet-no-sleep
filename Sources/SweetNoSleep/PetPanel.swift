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
    var showsWaitingBubble = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsPet(at: point) else { return nil }
        return super.hitTest(point)
    }

    private func containsPet(at point: NSPoint) -> Bool {
        let xInPanel = point.x
        let yInPanel = bounds.height - point.y // Convert AppKit's bottom-left origin to SwiftUI's top-left origin.
        let petSide = petSize + 48
        let petInsetX = (bounds.width - petSide) / 2
        let petInsetY = bubbleHeight

        if showsWaitingBubble,
           yInPanel <= PetWaitingBubble.height,
           abs(xInPanel - bounds.midX) <= PetWaitingBubble.width / 2 {
            return true
        }

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

    /// Space the visible bubble occupies above the pet.
    private var bubbleHeight: CGFloat {
        if showsWaitingBubble { return PetWaitingBubble.height }
        return showsBreakReminder ? PetBreakReminderBubble.height : 0
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
    private var wanderAnimator: PanelOriginAnimator?
    /// Bubbles currently on screen; they decide the panel's top inset.
    private var showsWaitingBubble = false
    private var showsBreakReminder = false
    // Validity flag for the current two-leg stroll. Set false by cancellation
    // so a leg-1 completion never starts leg 2 after the trip was killed.
    private var wanderTripValid = false
    private var cancellables = Set<AnyCancellable>()

    init(model: SweetNoSleepModel) {
        self.model = model
        model.$petSize.dropFirst().sink { [weak self] size in
            self?.updateSize(CGFloat(size))
        }.store(in: &cancellables)
        // @Published emits from willSet, so the visible bubble is derived from
        // the emitted values instead of re-reading the model here.
        Publishers.CombineLatest3(model.$agentSessions, model.$dismissedWaitingIDs, model.$isBreakDue)
            .dropFirst()
            .sink { [weak self] sessions, dismissed, isBreakDue in
                guard let self else { return }
                self.showsWaitingBubble = sessions.contains { session in
                    session.value.isWaiting && !dismissed.contains(session.key)
                }
                self.showsBreakReminder = isBreakDue
                self.updateSize(CGFloat(self.model.petSize))
            }
            .store(in: &cancellables)
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

        showsWaitingBubble = model.showsWaitingBubble
        showsBreakReminder = model.isBreakDue
        let size = panelSize(for: CGFloat(model.petSize))
        let rootView = PetDesktopView(
            model: model,
            onDragChanged: { [weak self] translation in self?.movePanel(by: translation) },
            onDragEnded: { [weak self] in self?.finishDragging() }
        )
        let layerView = PetLayerHitTestView(frame: NSRect(origin: .zero, size: size))
        layerView.petSize = CGFloat(model.petSize)
        layerView.showsBreakReminder = showsBreakReminder
        layerView.showsWaitingBubble = showsWaitingBubble
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
        cancelWanderAnimation()
        model.endWandering()
        panel?.orderOut(nil)
    }

    func close() {
        wanderTimer?.invalidate()
        wanderTimer = nil
        cancelWanderAnimation()
        model.endWandering()
        panel?.orderOut(nil)
        panel = nil
        cancellables.removeAll()
    }

    private func movePanel(by translation: CGSize) {
        guard let panel else { return }
        if dragOrigin == nil {
            cancelWanderAnimation()
            dragOrigin = panel.frame.origin
        }
        guard let dragOrigin else { return }
        panel.setFrameOrigin(NSPoint(
            x: dragOrigin.x + translation.width,
            y: dragOrigin.y - translation.height
        ))
    }

    private func finishDragging() {
        guard let panel else { return }
        dragOrigin = nil
        PetPanelPosition.store(panel.frame.origin)
    }

    private func updateSize(_ petSize: CGFloat) {
        guard let panel else { return }
        let size = panelSize(for: petSize)
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
            layerView.showsBreakReminder = showsBreakReminder
            layerView.showsWaitingBubble = showsWaitingBubble
            layerView.frame = NSRect(origin: .zero, size: size)
        }
    }

    private func updateLevel(isPinned: Bool) {
        guard let panel else { return }
        panel.isFloatingPanel = isPinned
        panel.level = isPinned ? .floating : .normal
    }

    private func panelSize(for petSize: CGFloat) -> NSSize {
        let petSide = petSize + 48
        // Waiting for an agent answer wins over the break reminder, exactly as
        // in PetDesktopView.
        if showsWaitingBubble {
            return NSSize(width: max(petSide, PetWaitingBubble.width), height: petSide + PetWaitingBubble.height)
        }
        if showsBreakReminder {
            return NSSize(width: max(petSide, PetBreakReminderBubble.width), height: petSide + PetBreakReminderBubble.height)
        }
        return NSSize(width: petSide, height: petSide)
    }

    private func restoredOrigin(for size: NSSize) -> NSPoint {
        if let origin = PetPanelPosition.restore() {
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
        cancelWanderAnimation()
        model.endWandering()
        guard enabled, model.isPetVisible, panel?.isVisible == true else { return }
        scheduleInitialWander()
    }

    private func scheduleInitialWander() {
        wanderTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wanderTimer = nil
                self.wanderOnce()
                self.scheduleRepeatingWander()
            }
        }
    }

    private func scheduleRepeatingWander() {
        guard model.roamingEnabled, model.isPetVisible, panel?.isVisible == true else { return }
        wanderTimer = Timer.scheduledTimer(withTimeInterval: 28, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.wanderOnce()
            }
        }
    }

    private func wanderOnce() {
        guard let panel,
              panel.isVisible,
              model.roamingEnabled,
              model.animationsEnabled,
              !model.isBreakDue,
              !model.hasWaitingAgent,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              model.mood != .dragging
        else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) ?? NSScreen.main else { return }

        var safeFrame = screen.visibleFrame.insetBy(dx: 18, dy: 18)
        safeFrame.size.width = max(safeFrame.width - panel.frame.width, 1)
        safeFrame.size.height = max(safeFrame.height - panel.frame.height, 1)
        let start = panel.frame.origin
        // Final target, kept away from the cursor so the pet never strolls under it.
        let target = pickTargetAvoidingCursor(in: safeFrame)
        // Curved path: midpoint pushed perpendicular to the trip, then away from cursor.
        let midpoint = curvedMidpoint(from: start, to: target, in: safeFrame)

        guard model.beginWandering() else { return }
        cancelWanderAnimation()
        wanderTripValid = true
        let animator = PanelOriginAnimator()
        wanderAnimator = animator
        // Leg 1: start -> midpoint. Leg 2 starts from its completion handler.
        animator.animate(
            panel: panel,
            to: midpoint,
            onStep: { origin in
                PetPanelPosition.store(origin)
            },
            completion: { [weak self] in
                guard let self else { return }
                // Trip was cancelled mid-flight: drop it without closing the mood state twice.
                guard self.wanderTripValid else { return }
                guard let panel = self.panel, panel.isVisible else {
                    self.wanderTripValid = false
                    self.wanderAnimator = nil
                    self.model.endWandering()
                    return
                }
                // Leg 2: midpoint -> final target. Single endWandering/poke/finishDragging
                // for the whole trip happens here.
                animator.animate(
                    panel: panel,
                    to: target,
                    onStep: { origin in
                        PetPanelPosition.store(origin)
                    },
                    completion: { [weak self] in
                        guard let self else { return }
                        guard self.wanderTripValid else { return }
                        self.wanderTripValid = false
                        self.wanderAnimator = nil
                        self.model.endWandering()
                        self.finishDragging()
                        if !self.model.isBreakDue {
                            self.model.poke()
                        }
                    }
                )
            }
        )
    }

    // MARK: Curved stroll helpers

    /// Picks a stroll target outside a 160pt cursor exclusion zone.
    /// Resamples up to 8 times; falls back to the farthest candidate seen.
    private func pickTargetAvoidingCursor(in safeFrame: NSRect) -> NSPoint {
        // NSEvent.mouseLocation already uses bottom-left origin screen coords,
        // directly comparable with visibleFrame-based points. No flip needed.
        let cursor = NSEvent.mouseLocation
        let exclusionRadius: CGFloat = 160
        var farthest = randomPoint(in: safeFrame)
        var farthestDistance = distance(from: farthest, to: cursor)
        // Check the initial candidate first.
        if farthestDistance >= exclusionRadius { return farthest }
        for _ in 0..<8 {
            let candidate = randomPoint(in: safeFrame)
            let dist = distance(from: candidate, to: cursor)
            if dist > farthestDistance {
                farthest = candidate
                farthestDistance = dist
            }
            if dist >= exclusionRadius { return candidate }
        }
        // All candidates were too close: take the farthest one.
        return farthest
    }

    private func randomPoint(in safeFrame: NSRect) -> NSPoint {
        NSPoint(
            x: CGFloat.random(in: safeFrame.minX...safeFrame.maxX),
            y: CGFloat.random(in: safeFrame.minY...safeFrame.maxY)
        )
    }

    /// Returns the midpoint of (start, target) pushed perpendicular by a random
    /// 25-40% of the trip length, then nudged away from the cursor. Clamped to safeFrame.
    private func curvedMidpoint(from start: NSPoint, to target: NSPoint, in safeFrame: NSRect) -> NSPoint {
        let center = NSPoint(x: (start.x + target.x) / 2, y: (start.y + target.y) / 2)
        let dx = target.x - start.x
        let dy = target.y - start.y
        let length = hypot(dx, dy)
        guard length >= 1 else { return clampToSafeFrame(center, in: safeFrame) }
        // Perpendicular unit vector.
        let perp = NSPoint(x: -dy / length, y: dx / length)
        let magnitude = length * CGFloat.random(in: 0.25...0.40)
        let sign: CGFloat = Bool.random() ? 1 : -1
        var midpoint = NSPoint(
            x: center.x + perp.x * magnitude * sign,
            y: center.y + perp.y * magnitude * sign
        )
        // Push the midpoint away from the cursor so the curve bows around it.
        let cursor = NSEvent.mouseLocation
        let awayX = midpoint.x - cursor.x
        let awayY = midpoint.y - cursor.y
        let awayDist = hypot(awayX, awayY)
        let keepAwayRadius: CGFloat = 200
        if awayDist < keepAwayRadius {
            if awayDist >= 1 {
                let push = keepAwayRadius - awayDist
                midpoint.x += (awayX / awayDist) * push
                midpoint.y += (awayY / awayDist) * push
            } else {
                // Midpoint sits exactly on the cursor: reuse the perpendicular push.
                midpoint.x += perp.x * 120 * sign
                midpoint.y += perp.y * 120 * sign
            }
        }
        return clampToSafeFrame(midpoint, in: safeFrame)
    }

    private func clampToSafeFrame(_ point: NSPoint, in safeFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(point.x, safeFrame.minX), safeFrame.maxX),
            y: min(max(point.y, safeFrame.minY), safeFrame.maxY)
        )
    }

    private func distance(from a: NSPoint, to b: NSPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func cancelWanderAnimation() {
        // Invalidate the trip so a pending leg-1 completion cannot start leg 2.
        wanderTripValid = false
        wanderAnimator?.cancel()
        wanderAnimator = nil
    }
}
