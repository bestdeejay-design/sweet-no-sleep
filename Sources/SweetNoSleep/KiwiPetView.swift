import AppKit
import SwiftUI

struct PetRenderProfile {
    let breathingFrequency: Double
    let breathingAmplitude: Double
    let tailFrequency: Double
    let tailAmplitude: CGFloat
    let celebrationEffect: PetCelebrationEffect
}

struct PetPalette {
    let fur: Color
    let furLight: Color
    let outline: Color
    let innerEar: Color
    let iris: Color
    let accent: Color
    let cheek: Color
    let animation: PetRenderProfile

    static func palette(for skin: PetSkinDefinition) -> PetPalette {
        let source = skin.animation
        return PetPalette(
            fur: color(skin.colors.fur),
            furLight: color(skin.colors.furLight),
            outline: color(skin.colors.outline),
            innerEar: color(skin.colors.innerEar),
            iris: color(skin.colors.iris),
            accent: color(skin.colors.accent),
            cheek: color(skin.colors.cheek),
            animation: PetRenderProfile(
                breathingFrequency: source.breathingFrequency,
                breathingAmplitude: source.breathingAmplitude,
                tailFrequency: source.tailFrequency,
                tailAmplitude: CGFloat(source.tailAmplitude),
                celebrationEffect: source.celebrationEffect
            )
        )
    }

    private static func color(_ value: String) -> Color {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard let number = UInt(hex, radix: 16) else { return .gray }
        return Color(hex: number)
    }
}

struct PetDesktopView: View {
    @ObservedObject var model: SweetNoSleepModel
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?
    /// Reports the laid-out content size so the panel can resize in the same
    /// SwiftUI update that added or removed a bubble (issue #21 P0: resizing
    /// the panel from the model's willSet left one frame where the bubble was
    /// still laid out inside the shrunken panel, clipping the pet).
    var onContentSize: ((NSSize) -> Void)?

    private var petSide: CGFloat { PetPanelLayout.petSide(petSize: CGFloat(model.petSize)) }
    private var bubbleHeight: CGFloat {
        PetPanelLayout.bubbleHeight(showsWaitingBubble: model.showsWaitingBubble, isBreakDue: model.isBreakDue)
    }
    private var bubbleWidth: CGFloat {
        PetPanelLayout.contentWidth(petSize: CGFloat(model.petSize), showsWaitingBubble: model.showsWaitingBubble, isBreakDue: model.isBreakDue)
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.showsWaitingBubble {
                PetWaitingBubble(model: model)
            } else if model.isBreakDue {
                PetBreakReminderBubble(model: model)
            }
            KiwiPetView(model: model, onDragChanged: onDragChanged, onDragEnded: onDragEnded)
        }
        .frame(width: bubbleWidth, height: petSide + bubbleHeight, alignment: .top)
        .background(Color.clear)
        .background(
            PanelContentSizeReporter(
                size: PetPanelLayout.contentSize(
                    petSize: CGFloat(model.petSize),
                    showsWaitingBubble: model.showsWaitingBubble,
                    isBreakDue: model.isBreakDue
                ),
                onChange: onContentSize
            )
        )
    }
}

/// Fires `onChange` from `updateNSView`, i.e. inside the SwiftUI update
/// transaction that changed the content size, so the panel's AppKit frame and
/// the SwiftUI layout move together and the sprite never draws outside the
/// panel bounds for a frame.
private struct PanelContentSizeReporter: NSViewRepresentable {
    let size: NSSize
    let onChange: ((NSSize) -> Void)?

    final class View: NSView {
        var onChange: ((NSSize) -> Void)?
        private(set) var reportedSize: NSSize = .zero
    }

    func makeNSView(context: Context) -> View {
        let view = View()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: View, context: Context) {
        nsView.onChange = onChange
        guard nsView.reportedSize != size else { return }
        nsView.reportedSize = size
        onChange?(size)
    }
}

/// The waiting cue: the agent asked a question and needs a human answer.
/// The buttons only close the bubble - the agent keeps waiting in its own
/// window, so nothing here claims to answer for it.
struct PetWaitingBubble: View {
    static let width: CGFloat = PetPanelLayout.waitingBubbleWidth
    static let height: CGFloat = PetPanelLayout.waitingBubbleHeight

    @ObservedObject var model: SweetNoSleepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(AgentIndicator.waitingColor)
                Text(L10n.text("Agent is waiting"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            Text(L10n.text("Your approval is needed (y/n)."))
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let reason = model.agentWaitingReason {
                Text(reason)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 6) {
                Button(L10n.text("Approve")) {
                    model.dismissWaitingCue()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 9, weight: .medium, design: .rounded))

                Spacer(minLength: 0)

                Button(L10n.text("Not now")) {
                    model.dismissWaitingCue()
                }
                .buttonStyle(.borderedProminent)
                .tint(AgentIndicator.waitingColor)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: Self.width, height: Self.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AgentIndicator.waitingColor.opacity(0.34), lineWidth: 1)
        }
    }
}

struct PetBreakReminderBubble: View {
    static let width: CGFloat = PetPanelLayout.breakBubbleWidth
    static let height: CGFloat = PetPanelLayout.breakBubbleHeight

    @ObservedObject var model: SweetNoSleepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "eye.circle.fill")
                    .foregroundStyle(Color(hex: 0x5EAC70))
                Text(L10n.text("Short break"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            Text(L10n.text("Look away from your code and focus on something in the distance for about 20 seconds."))
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            HStack(spacing: 6) {
                Button(L10n.text("Snooze - 5 min")) {
                    model.dismissBreakReminder(snoozeMinutes: 5)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 9, weight: .medium, design: .rounded))

                Spacer(minLength: 0)

                Button(L10n.text("Break taken")) {
                    model.dismissBreakReminder()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x5EAC70))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: Self.width, height: Self.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: 0x5EAC70, opacity: 0.28), lineWidth: 1)
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        let binding = _window
        view.onWindowChange = { binding.wrappedValue = $0 }
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        let binding = _window
        nsView.onWindowChange = { binding.wrappedValue = $0 }
        DispatchQueue.main.async {
            if binding.wrappedValue !== nsView.window {
                binding.wrappedValue = nsView.window
            }
        }
    }
}

private final class WindowTrackingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

/// Smoothed frame-rate probe behind the hidden debug FPS overlay
/// (`defaults write <bundle> SNSDebugFPSOverlay -bool true`). The Canvas closure
/// is a pure function of the timeline date, so the probe keeps its own state.
final class FrameRateProbe {
    static let shared = FrameRateProbe()

    private let lock = NSLock()
    private var lastTime: Double = 0
    private var framesPerSecond: Double = 0

    func sample(_ time: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        if lastTime > 0 {
            let delta = time - lastTime
            if delta > 0, delta < 0.5 {
                let instant = 1.0 / delta
                framesPerSecond = framesPerSecond == 0 ? instant : framesPerSecond * 0.9 + instant * 0.1
            }
        }
        lastTime = time
        return framesPerSecond
    }
}

/// A tiny, asset-free cat character drawn in SwiftUI Canvas.
/// Its idle loop uses restrained secondary motion: breathing, blinks, a soft tail
/// sway and small expression changes. It follows Reduce Motion and can be dragged.
struct KiwiPetView: View {
    @ObservedObject var model: SweetNoSleepModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var sizeOverride: CGFloat? = nil
    var allowsDragging = true
    var tracksCursor = true
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?

    @State private var isDragging = false
    @State private var trackedWindow: NSWindow?

    /// Defaults key of the hidden FPS overlay used for 60 fps acceptance.
    static let debugFPSKey = "SNSDebugFPSOverlay"

    private var renderedSize: CGFloat {
        sizeOverride ?? CGFloat(model.petSize)
    }

    private var canvasSize: CGFloat { renderedSize + 48 }
    private var reduceMotion: Bool { systemReduceMotion || !model.animationsEnabled }

    /// Extra space above the pet when a bubble is visible, so the eyes keep
    /// tracking the pointer from the right place. Must match the bubble the
    /// layout actually shows (a dismissed cue occupies no space).
    private var topInset: CGFloat {
        PetPanelLayout.topInset(showsWaitingBubble: model.showsWaitingBubble, isBreakDue: model.isBreakDue)
    }

    var body: some View {
        TimelineView(
            .animation(
                // The display-refresh schedule: 60 fps while animated, so the
                // walk cycle, gaze and particles never step; Reduce Motion keeps
                // the slow static-pose cadence.
                minimumInterval: reduceMotion ? 0.12 : 1.0 / 60.0,
                paused: !model.isPetVisible
            )
        ) { timeline in
            Canvas { context, size in
                let skin = model.activeSkin
                let time = timeline.date.timeIntervalSinceReferenceDate
                Self.drawPet(
                    in: &context,
                    size: size,
                    time: time,
                    mood: model.mood,
                    palette: .palette(for: skin),
                    gaze: tracksCursor ? cursorGaze(canvasSize: canvasSize, topInset: topInset) : .zero,
                    reducedMotion: reduceMotion,
                    agentLight: model.agentIndicatorEnabled ? model.agentLightState : .off,
                    agentCount: model.agentIndicatorEnabled ? model.activeAgentCount : 0,
                    attention: model.hasWaitingAgent ? .question : nil,
                    sprite: CharacterSpriteStore.shared.sprite(for: skin)
                )
                if UserDefaults.standard.bool(forKey: Self.debugFPSKey) {
                    let fps = FrameRateProbe.shared.sample(time)
                    if fps > 1 {
                        context.draw(
                            Text("\(Int(fps)) fps")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.green),
                            at: CGPoint(x: 6, y: 4),
                            anchor: .topLeading
                        )
                    }
                }
            }
            .frame(width: canvasSize, height: canvasSize)
        }
        .frame(width: canvasSize, height: canvasSize)
        .background {
            if tracksCursor {
                WindowAccessor(window: $trackedWindow)
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture { model.poke() }
        .accessibilityElement()
        .accessibilityLabel(L10n.format("%@, the Sweet No Sleep pet", model.activeSkin.name))
        .accessibilityHint(allowsDragging
            ? L10n.text("Click to say hello, or drag the pet to move it.")
            : L10n.text("Click to say hello."))
    }

    private func cursorGaze(canvasSize: CGFloat, topInset: CGFloat) -> CGPoint {
        guard let window = trackedWindow else { return .zero }
        let frame = window.frame
        let catCenter = CGPoint(x: frame.midX, y: frame.maxY - topInset - canvasSize / 2)
        let cursor = NSEvent.mouseLocation
        let range = max(canvasSize * 0.48, 1)
        return CGPoint(
            x: min(max((cursor.x - catCenter.x) / range, -1), 1),
            y: min(max((catCenter.y - cursor.y) / range, -1), 1)
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard allowsDragging else { return }
                if !isDragging {
                    isDragging = true
                    model.beginDragging()
                }
                onDragChanged?(value.translation)
            }
            .onEnded { _ in
                guard allowsDragging else { return }
                isDragging = false
                onDragEnded?()
                model.endDragging()
            }
    }

    // MARK: Illustration

    private static func drawPet(
        in context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        mood: KiwiMood,
        palette: PetPalette,
        gaze: CGPoint,
        reducedMotion: Bool,
        agentLight: AgentLightState,
        agentCount: Int,
        attention: AttentionSymbol?,
        sprite: CharacterSprite?
    ) {
        if let sprite {
            SpriteCharacterRenderer.draw(
                in: &context,
                size: size,
                time: time,
                mood: mood,
                palette: palette,
                sprite: sprite,
                light: agentLight,
                agentCount: agentCount,
                attention: attention,
                gaze: gaze,
                animated: !reducedMotion
            )
            return
        }

        let radius = min(size.width, size.height) * 0.335
        let center = CGPoint(x: size.width * 0.50, y: size.height * 0.55)
        let headCenter = CGPoint(x: center.x, y: center.y - radius * 0.23)
        let profile = palette.animation
        let isDancing = mood == .dancing && !reducedMotion
        let isStretching = mood == .stretching
        let isWaiting = mood == .waitingForApproval
        let danceSway = isDancing ? CGFloat(sin(time * 6.2)) * radius * 0.055 : 0
        let danceBounce = isDancing ? CGFloat(abs(sin(time * 6.2))) * radius * 0.075 : 0
        let stretchLift = isStretching ? radius * 0.035 : 0
        // A working agent makes the pet breathe a little quicker: a cheap
        // "I can see the work" cue that costs nothing and respects Reduce Motion.
        let feedBounce = agentLight == .working
        let breathFrequency = profile.breathingFrequency * (feedBounce ? 1.25 : 1.0)
        let breath: CGFloat = reducedMotion ? 0 : CGFloat(sin(time * breathFrequency)) * CGFloat(profile.breathingAmplitude)
        let workBob: CGFloat = (feedBounce && !reducedMotion) ? CGFloat(abs(sin(time * 2.4))) * radius * 0.012 : 0
        let bob: CGFloat = reducedMotion ? 0 : CGFloat(sin(time * 1.45)) * radius * 0.018
        let bodyCenter = CGPoint(x: center.x + danceSway, y: center.y + bob - danceBounce - workBob)
        let headBob = CGPoint(x: headCenter.x + danceSway * 0.32, y: headCenter.y + bob - danceBounce * 0.42 - stretchLift - workBob)
        let posedBreath = breath + (isStretching ? 0.045 : 0)

        if mood == .working || mood == .celebrating || mood == .dancing || mood == .breakReminder || isWaiting {
            let haloRect = CGRect(
                x: center.x - radius * 1.16,
                y: center.y - radius * 0.98,
                width: radius * 2.32,
                height: radius * 2.32
            )
            let haloOpacity = mood == .celebrating || mood == .dancing ? 0.15 : ((mood == .breakReminder || isWaiting) ? 0.13 : 0.08)
            let haloColor = isWaiting ? AgentIndicator.waitingColor : palette.accent
            context.fill(Path(ellipseIn: haloRect), with: .color(haloColor.opacity(haloOpacity)))
        }

        drawTail(in: &context, center: bodyCenter, radius: radius, time: time, palette: palette, mood: mood, reducedMotion: reducedMotion)
        drawBody(in: &context, center: bodyCenter, radius: radius, palette: palette, breath: posedBreath)
        // Gentle head tilt: subtle rotation of the head/face group during calm moods.
        let headTilt = Self.headTiltAngle(time: time, mood: mood, reducedMotion: reducedMotion)
        if headTilt != 0 {
            context.concatenate(CGAffineTransform(translationX: headBob.x, y: headBob.y))
            context.concatenate(CGAffineTransform(rotationAngle: headTilt))
            context.concatenate(CGAffineTransform(translationX: -headBob.x, y: -headBob.y))
        }
        drawHead(in: &context, center: headBob, radius: radius, palette: palette, breath: posedBreath)
        drawFace(in: &context, center: headBob, radius: radius, time: time, palette: palette, mood: mood, gaze: gaze, reducedMotion: reducedMotion)
        drawCheekHeart(in: &context, headCenter: headBob, radius: radius, time: time, palette: palette, mood: mood, reducedMotion: reducedMotion)
        if headTilt != 0 {
            context.concatenate(CGAffineTransform(translationX: headBob.x, y: headBob.y))
            context.concatenate(CGAffineTransform(rotationAngle: -headTilt))
            context.concatenate(CGAffineTransform(translationX: -headBob.x, y: -headBob.y))
        }
        drawPaws(in: &context, center: bodyCenter, radius: radius, palette: palette, time: time, mood: mood, reducedMotion: reducedMotion)
        drawKiwiBadge(
            in: &context,
            center: CGPoint(x: center.x + danceSway * 0.45, y: center.y + radius * 0.40 + bob - danceBounce - workBob),
            radius: radius,
            palette: palette,
            time: time,
            mood: mood,
            reducedMotion: reducedMotion,
            agentLight: agentLight,
            agentCount: agentCount
        )

        if mood == .celebrating || mood == .dancing {
            drawCelebrationEffect(
                in: &context,
                center: center,
                radius: radius,
                time: time,
                palette: palette,
                effect: profile.celebrationEffect,
                reducedMotion: reducedMotion
            )
        }
        if mood == .curious || mood == .breakReminder || isWaiting {
            let sparkle = CGPoint(x: center.x + radius * 0.83, y: center.y - radius * 0.82)
            let sparkleColor = isWaiting ? AgentIndicator.waitingColor : palette.accent
            context.fill(PetShapes.star(center: sparkle, outerRadius: radius * 0.11, innerRadius: radius * 0.045), with: .color(sparkleColor.opacity(0.90)))
        }
        if let attention {
            AgentIndicator.drawGlyphBadge(
                in: &context,
                center: AgentIndicator.attentionGlyphCenter(in: size),
                height: AgentIndicator.attentionGlyphHeight(in: size),
                symbol: attention
            )
        }
    }

    private static func drawBody(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, palette: PetPalette, breath: CGFloat) {
        let bodyRect = CGRect(
            x: center.x - radius * 0.64,
            y: center.y - radius * 0.10,
            width: radius * 1.28,
            height: radius * (1.10 + breath)
        )
        let body = Path(ellipseIn: bodyRect)
        context.fill(
            body,
            with: .linearGradient(
                Gradient(colors: [palette.furLight, palette.fur]),
                startPoint: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
                endPoint: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY)
            )
        )
        context.stroke(body, with: .color(palette.outline), style: StrokeStyle(lineWidth: max(radius * 0.045, 1.5)))

        // Soft belly, kept subtle so the chest badge remains the focal detail.
        let bellyRect = CGRect(x: center.x - radius * 0.39, y: center.y + radius * 0.16, width: radius * 0.78, height: radius * 0.67)
        context.fill(Path(ellipseIn: bellyRect), with: .color(palette.furLight.opacity(0.50)))
    }

    private static func drawHead(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, palette: PetPalette, breath: CGFloat) {
        let head = catHeadPath(center: center, radius: radius * (1 + breath * 0.3))
        context.fill(
            head,
            with: .linearGradient(
                Gradient(colors: [palette.furLight, palette.fur]),
                startPoint: CGPoint(x: center.x - radius * 0.8, y: center.y - radius),
                endPoint: CGPoint(x: center.x + radius * 0.8, y: center.y + radius * 0.8)
            )
        )
        context.stroke(head, with: .color(palette.outline), style: StrokeStyle(lineWidth: max(radius * 0.045, 1.5), lineJoin: .round))

        for side in [-1.0, 1.0] {
            let ear = innerEarPath(center: center, radius: radius, side: side)
            context.fill(ear, with: .color(palette.innerEar.opacity(0.83)))
        }

        // Three tiny leaves make the Kiwi identity readable without a bitmap.
        let leafBase = CGPoint(x: center.x, y: center.y - radius * 0.76)
        PetShapes.leaf(in: &context, from: leafBase, to: CGPoint(x: center.x - radius * 0.17, y: center.y - radius * 1.00), radius: radius * 0.105, color: palette.accent)
        PetShapes.leaf(in: &context, from: leafBase, to: CGPoint(x: center.x + radius * 0.16, y: center.y - radius * 1.02), radius: radius * 0.105, color: palette.accent.opacity(0.9))
        PetShapes.leaf(in: &context, from: leafBase, to: CGPoint(x: center.x, y: center.y - radius * 1.08), radius: radius * 0.11, color: palette.accent)
    }

    private static func drawFace(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double, palette: PetPalette, mood: KiwiMood, gaze: CGPoint, reducedMotion: Bool) {
        let isHappy = mood == .celebrating || mood == .dancing
        let isResting = mood == .resting || mood == .stretching
        // Wide eyes and an open mouth read as "I have a question" while waiting.
        let eyesWide = mood == .curious || mood == .breakReminder || mood == .waitingForApproval
        let blinkCycle = time.truncatingRemainder(dividingBy: 4.6)
        let isBlinking = !reducedMotion && blinkCycle < 0.14
        let eyeY = center.y + radius * 0.06
        let eyeGap = radius * 0.285
        let eyeWidth = radius * 0.105
        let eyeHeight = radius * 0.155

        // Cheeks sit behind the whiskers and keep the expression warm at small sizes.
        for side in [-1.0, 1.0] {
            let cheek = CGRect(x: center.x + CGFloat(side) * radius * 0.39 - radius * 0.12, y: center.y + radius * 0.31, width: radius * 0.24, height: radius * 0.12)
            context.fill(Path(ellipseIn: cheek), with: .color(palette.cheek.opacity(0.46)))
        }

        for side in [-1.0, 1.0] {
            let eyeCenter = CGPoint(x: center.x + CGFloat(side) * eyeGap, y: eyeY)
            if isHappy || isResting || isBlinking {
                let arc = closedEyePath(center: eyeCenter, radius: eyeWidth * 1.04, happy: isHappy)
                context.stroke(arc, with: .color(palette.outline), style: StrokeStyle(lineWidth: max(radius * 0.055, 1.7), lineCap: .round))
            } else {
                let eyeHeightScale: CGFloat = eyesWide ? 2.15 : 1.7
                let eyeRect = CGRect(x: eyeCenter.x - eyeWidth, y: eyeCenter.y - eyeHeight * 0.52, width: eyeWidth * 2, height: eyeHeight * eyeHeightScale)
                context.fill(Path(ellipseIn: eyeRect), with: .color(palette.outline))
                let gazeX = CGFloat(gaze.x) * radius * 0.052
                let gazeY = CGFloat(gaze.y) * radius * 0.050
                let irisRect = eyeRect.insetBy(dx: eyeWidth * 0.22, dy: eyeHeight * 0.14).offsetBy(dx: gazeX, dy: gazeY)
                context.fill(Path(ellipseIn: irisRect), with: .color(palette.iris))
                let pupilRect = CGRect(x: eyeCenter.x - eyeWidth * 0.31, y: eyeCenter.y - eyeHeight * 0.33, width: eyeWidth * 0.62, height: eyeHeight * 0.72)
                    .offsetBy(dx: gazeX * 1.12, dy: gazeY * 1.12)
                context.fill(Path(ellipseIn: pupilRect), with: .color(Color(hex: 0x30282C)))
                let shineRect = CGRect(x: eyeCenter.x - eyeWidth * 0.22, y: eyeCenter.y - eyeHeight * 0.38, width: eyeWidth * 0.22, height: eyeWidth * 0.22)
                    .offsetBy(dx: gazeX * 0.78, dy: gazeY * 0.78)
                context.fill(Path(ellipseIn: shineRect), with: .color(.white.opacity(0.94)))
            }
        }

        // Small triangular nose and a soft smile.
        let nose = Path { path in
            path.move(to: CGPoint(x: center.x, y: center.y + radius * 0.24))
            path.addQuadCurve(to: CGPoint(x: center.x - radius * 0.085, y: center.y + radius * 0.17), control: CGPoint(x: center.x - radius * 0.08, y: center.y + radius * 0.16))
            path.addQuadCurve(to: CGPoint(x: center.x + radius * 0.085, y: center.y + radius * 0.17), control: CGPoint(x: center.x, y: center.y + radius * 0.27))
            path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius * 0.24), control: CGPoint(x: center.x + radius * 0.08, y: center.y + radius * 0.16))
        }
        context.fill(nose, with: .color(palette.innerEar))

        if eyesWide {
            let openMouth = CGRect(x: center.x - radius * 0.055, y: center.y + radius * 0.30, width: radius * 0.11, height: radius * 0.13)
            context.fill(Path(ellipseIn: openMouth), with: .color(palette.outline))
            context.fill(Path(ellipseIn: openMouth.insetBy(dx: radius * 0.025, dy: radius * 0.035)), with: .color(palette.innerEar))
        } else {
            var smile = Path()
            smile.move(to: CGPoint(x: center.x, y: center.y + radius * 0.24))
            smile.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.31))
            smile.move(to: CGPoint(x: center.x, y: center.y + radius * 0.31))
            smile.addQuadCurve(to: CGPoint(x: center.x - radius * 0.12, y: center.y + radius * 0.29), control: CGPoint(x: center.x - radius * 0.07, y: center.y + radius * 0.42))
            smile.move(to: CGPoint(x: center.x, y: center.y + radius * 0.31))
            smile.addQuadCurve(to: CGPoint(x: center.x + radius * 0.12, y: center.y + radius * 0.29), control: CGPoint(x: center.x + radius * 0.07, y: center.y + radius * 0.42))
            context.stroke(smile, with: .color(palette.outline), style: StrokeStyle(lineWidth: max(radius * 0.035, 1.2), lineCap: .round))
        }

        // Fine whiskers; intentionally low contrast, so they don't overpower the face.
        for side in [-1.0, 1.0] {
            for offset in [-0.08, 0.04, 0.16] {
                var whisker = Path()
                let start = CGPoint(x: center.x + CGFloat(side) * radius * 0.49, y: center.y + radius * (0.25 + offset))
                let end = CGPoint(x: center.x + CGFloat(side) * radius * 0.84, y: center.y + radius * (0.18 + offset * 1.8))
                whisker.move(to: start)
                whisker.addLine(to: end)
                context.stroke(whisker, with: .color(palette.outline.opacity(0.45)), style: StrokeStyle(lineWidth: max(radius * 0.018, 0.7), lineCap: .round))
            }
        }
    }

    private static func drawPaws(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, palette: PetPalette, time: Double, mood: KiwiMood, reducedMotion: Bool) {
        let isMoving = mood == .walking || mood == .dancing
        let isWaiting = mood == .waitingForApproval
        let step: CGFloat = isMoving && !reducedMotion ? CGFloat(sin(time * (mood == .dancing ? 6.2 : 8))) * radius * 0.065 : 0
        let lift: CGFloat = reducedMotion ? 0 : (mood == .stretching ? radius * 0.11 : (mood == .dancing ? CGFloat(abs(sin(time * 6.2))) * radius * 0.12 : 0))
        // Attention pose: the right front paw stays raised while the agent waits.
        // The raise is static (visible with animations off) and only the small
        // wave depends on motion.
        let raisedPaw: CGFloat = isWaiting ? radius * 0.30 : 0
        let wave: CGFloat = (isWaiting && !reducedMotion) ? CGFloat(sin(time * 3.0)) * radius * 0.035 : 0
        for (index, side) in [-1.0, 1.0].enumerated() {
            let offset = index == 0 ? step : -step
            let isRaisedPaw = isWaiting && index == 1
            let paw = CGRect(
                x: center.x + CGFloat(side) * radius * 0.30 - radius * 0.20 + (isRaisedPaw ? -wave * 0.4 : 0),
                y: center.y + radius * 0.70 + offset - lift - (isRaisedPaw ? raisedPaw + wave : 0),
                width: radius * 0.40,
                height: radius * 0.20
            )
            context.fill(Path(ellipseIn: paw), with: .color(palette.furLight))
            context.stroke(Path(ellipseIn: paw), with: .color(palette.outline.opacity(0.75)), style: StrokeStyle(lineWidth: max(radius * 0.025, 0.9)))
        }
    }

    private static func drawKiwiBadge(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, palette: PetPalette, time: Double, mood: KiwiMood, reducedMotion: Bool, agentLight: AgentLightState = .off, agentCount: Int = 0) {
        let pulse: CGFloat
        if !reducedMotion && mood == .working {
            pulse = 1 + CGFloat(sin(time * 2.8)) * 0.035
        } else if !reducedMotion && mood == .dancing {
            pulse = 1 + CGFloat(sin(time * 6.2)) * 0.085
        } else {
            pulse = 1
        }
        let badgeRadius = radius * 0.205 * pulse
        let badge = CGRect(x: center.x - badgeRadius, y: center.y - badgeRadius, width: badgeRadius * 2, height: badgeRadius * 2)
        context.fill(Path(ellipseIn: badge), with: .color(palette.accent))
        context.stroke(Path(ellipseIn: badge), with: .color(palette.outline.opacity(0.76)), style: StrokeStyle(lineWidth: max(radius * 0.028, 1)))

        // While agents are connected the badge core becomes the status light,
        // and the active-session count sits just below it.
        if agentLight != .off {
            AgentIndicator.drawBadge(
                in: &context,
                center: center,
                radius: radius,
                palette: palette,
                light: agentLight,
                count: agentCount,
                animated: !reducedMotion,
                time: time
            )
            return
        }

        let coreRadius = badgeRadius * 0.58
        let core = CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
        context.fill(Path(ellipseIn: core), with: .color(Color(hex: 0xF5EFCF)))
        for index in 0..<6 {
            let angle = Double(index) * .pi / 3
            let seedCenter = CGPoint(x: center.x + CGFloat(cos(angle)) * coreRadius * 0.62, y: center.y + CGFloat(sin(angle)) * coreRadius * 0.62)
            let seed = CGRect(x: seedCenter.x - radius * 0.018, y: seedCenter.y - radius * 0.018, width: radius * 0.036, height: radius * 0.036)
            context.fill(Path(ellipseIn: seed), with: .color(palette.outline.opacity(0.70)))
        }
        let centerSeed = CGRect(x: center.x - radius * 0.022, y: center.y - radius * 0.022, width: radius * 0.044, height: radius * 0.044)
        context.fill(Path(ellipseIn: centerSeed), with: .color(palette.outline.opacity(0.60)))
    }

    private static func drawTail(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double, palette: PetPalette, mood: KiwiMood, reducedMotion: Bool) {
        let profile = palette.animation
        let amplitude = mood == .dancing
            ? profile.tailAmplitude * 1.8
            : (mood == .working ? profile.tailAmplitude : profile.tailAmplitude * 0.55)
        let wag: CGFloat = reducedMotion ? 0 : CGFloat(sin(time * profile.tailFrequency)) * radius * amplitude
        let lifted: CGFloat = (mood == .celebrating || mood == .dancing) ? -radius * 0.18 : (mood == .stretching ? -radius * 0.10 : 0)
        var tail = Path()
        let base = CGPoint(x: center.x + radius * 0.52, y: center.y + radius * 0.46)
        let tip = CGPoint(x: center.x + radius * 1.24, y: center.y + radius * 0.22 + wag + lifted)
        tail.move(to: base)
        tail.addCurve(
            to: tip,
            control1: CGPoint(x: center.x + radius * 0.95, y: center.y + radius * 0.67 + wag * 0.55),
            control2: CGPoint(x: center.x + radius * 1.26, y: center.y + radius * 0.77 + wag + lifted)
        )
        context.stroke(tail, with: .color(palette.outline), style: StrokeStyle(lineWidth: radius * 0.19, lineCap: .round))
        context.stroke(tail, with: .color(palette.fur), style: StrokeStyle(lineWidth: radius * 0.125, lineCap: .round))
        let tipDot = CGRect(x: tip.x - radius * 0.055, y: tip.y - radius * 0.055, width: radius * 0.11, height: radius * 0.11)
        context.fill(Path(ellipseIn: tipDot), with: .color(palette.furLight))
    }

    // Gentle head tilt roughly every 18s during calm moods (idle/working).
    // Active for 2s per cycle with smoothstep ease in/out, alternating direction.
    // Frozen straight when reduced motion is on.
    private static func headTiltAngle(time: Double, mood: KiwiMood, reducedMotion: Bool) -> CGFloat {
        guard !reducedMotion, mood == .idle || mood == .working else { return 0 }
        let period = 18.0
        let duration = 2.0
        let phase = time.truncatingRemainder(dividingBy: period)
        guard phase >= 0, phase < duration else { return 0 }
        let t = phase / duration // 0...1
        func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
            let clamped = min(max((x - a) / (b - a), 0), 1)
            return clamped * clamped * (3 - 2 * clamped)
        }
        let envelope = smoothstep(0, 0.4, t) * (1 - smoothstep(0.6, 1.0, t))
        let cycle = Int(floor(time / period))
        let direction: Double = cycle % 2 == 0 ? 1 : -1
        let maxAngle = 7.0 * Double.pi / 180.0 // subtle, up to ~7 degrees
        return CGFloat(direction * maxAngle * envelope)
    }

    // Small soft heart in cheek color during celebrating, with light pulsation.
    // No celebration progress is plumbed into drawPet, so opacity is a steady
    // soft value; reduced motion renders a static heart.
    private static func drawCheekHeart(
        in context: inout GraphicsContext,
        headCenter: CGPoint,
        radius: CGFloat,
        time: Double,
        palette: PetPalette,
        mood: KiwiMood,
        reducedMotion: Bool
    ) {
        guard mood == .celebrating else { return }
        let pulse = reducedMotion ? 1.0 : 1.0 + 0.08 * sin(time * 6.0)
        let heartSize = radius * 0.16 * CGFloat(pulse)
        let heartCenter = CGPoint(x: headCenter.x + radius * 0.52, y: headCenter.y + radius * 0.33)
        context.fill(PetShapes.heart(center: heartCenter, size: heartSize), with: .color(palette.cheek.opacity(0.85)))
    }

    private static func drawCelebrationEffect(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        palette: PetPalette,
        effect: PetCelebrationEffect,
        reducedMotion: Bool
    ) {
        // Global envelope: ultra-smooth fades across the celebration window.
        let alpha = PetShapes.celebrationAlpha(time: time, reducedMotion: reducedMotion)
        guard alpha > 0.01 else { return }
        // Normalized fade factor (1.0 at envelope peak) so base opacities keep
        // their designed visibility while still fading smoothly in/out.
        let fade = alpha / 0.9

        PetShapes.celebrationBase(
            in: &context,
            center: center,
            radius: radius,
            time: time,
            palette: palette,
            fade: fade,
            reducedMotion: reducedMotion
        )

        let twinkle = reducedMotion ? 0.86 : CGFloat(0.72 + (sin(time * 7) + 1) * 0.14)
        switch effect {
        case .leaves:
            // 6 leaves at ~1.5-2x size, each with its own drift/twinkle phase.
            let leaves: [(CGFloat, CGFloat, CGFloat, CGFloat, Double)] = [
                (-0.84, -0.24, -0.19, -0.39, 0.0),
                (0.82, -0.18, 0.20, -0.39, 1.1),
                (-0.95, 0.30, -0.16, -0.34, 2.2),
                (0.96, 0.32, 0.16, -0.34, 3.3),
                (-0.45, -0.95, -0.10, -0.36, 4.4),
                (0.48, -0.97, 0.10, -0.36, 5.3)
            ]
            let leafScales: [CGFloat] = [0.24, 0.26, 0.21, 0.22, 0.20, 0.23]
            for (index, leaf) in leaves.enumerated() {
                let (ax, ay, dx, dy, phase) = leaf
                let drift: CGFloat = reducedMotion ? 0 : CGFloat(sin(time * 4 + phase)) * radius * 0.035
                let from = CGPoint(x: center.x + ax * radius, y: center.y + ay * radius + drift)
                let to = CGPoint(x: from.x + dx * radius, y: from.y + dy * radius + drift * 0.5)
                let shimmer: CGFloat = reducedMotion ? 1.0 : 0.82 + 0.18 * CGFloat(0.5 + 0.5 * sin(time * 7 + phase))
                PetShapes.leaf(
                    in: &context,
                    from: from,
                    to: to,
                    radius: radius * leafScales[index] * (reducedMotion ? 1.0 : twinkle),
                    color: palette.accent.opacity(min(0.92 * shimmer * fade, 1.0))
                )
            }
        case .moonDust:
            // Crescent at 1.5x plus 12 individually-phased sparks.
            let moonCenter = CGPoint(x: center.x + radius * 0.98, y: center.y - radius * 0.42)
            let crescentRadius = radius * 0.17 * 1.5
            let moonPulse: CGFloat = reducedMotion ? 1.0 : 1.0 + 0.05 * CGFloat(sin(time * 5.0 + 0.7))
            context.fill(
                PetShapes.crescent(center: moonCenter, radius: crescentRadius * moonPulse),
                with: .color(palette.accent.opacity(min(0.92 * fade, 1.0)))
            )
            for i in 0..<12 {
                let phase = Double(i) * 0.9
                let angle = Double(i) * .pi * 2 / 12 + 0.3
                let dist: CGFloat = reducedMotion ? radius * 0.38 : radius * (0.38 + 0.08 * CGFloat(sin(time * 2.5 + phase)))
                let point = CGPoint(
                    x: moonCenter.x + CGFloat(cos(angle)) * dist,
                    y: moonCenter.y + CGFloat(sin(angle)) * dist
                )
                let flicker: CGFloat = reducedMotion ? 1.0 : 0.55 + 0.45 * CGFloat(0.5 + 0.5 * sin(time * 6.0 + phase * 1.7))
                let scale: CGFloat = 0.055 + 0.03 * CGFloat(0.5 + 0.5 * sin(phase * 2.3))
                context.fill(
                    PetShapes.star(center: point, outerRadius: radius * scale * flicker, innerRadius: radius * scale * 0.30),
                    with: .color(palette.furLight.opacity(min(0.95 * flicker * fade, 1.0)))
                )
            }
        case .berryHearts:
            // Same heart shapes/positions; envelope fades + +-10% size pulsation.
            let hearts: [(CGFloat, CGFloat, CGFloat, Double)] = [
                (-0.98, -0.42, 0.13, 0.0), (0.98, -0.55, 0.16, 2.1), (-0.89, 0.24, 0.10, 4.2)
            ]
            for (x, y, scale, phase) in hearts {
                let point = CGPoint(x: center.x + x * radius, y: center.y + y * radius)
                let beat: CGFloat = reducedMotion ? 1.0 : 1.0 + 0.10 * CGFloat(sin(time * 6.0 + phase))
                context.fill(
                    PetShapes.heart(center: point, size: radius * scale * twinkle * beat),
                    with: .color(palette.cheek.opacity(min(0.92 * fade, 1.0)))
                )
            }
        case .starburst:
            let stars: [(CGFloat, CGFloat, CGFloat)] = [(-1.00, -0.48, 0.11), (0.98, -0.53, 0.14), (-0.94, 0.25, 0.085), (0.88, 0.28, 0.09)]
            for (x, y, scale) in stars {
                let point = CGPoint(x: center.x + x * radius, y: center.y + y * radius)
                context.fill(PetShapes.star(center: point, outerRadius: radius * scale * twinkle, innerRadius: radius * scale * 0.32), with: .color(palette.accent.opacity(min(0.95 * fade, 1.0))))
            }
        }
    }

    private static func catHeadPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x - radius * 0.76, y: center.y + radius * 0.44))
        path.addCurve(
            to: CGPoint(x: center.x - radius * 0.88, y: center.y - radius * 0.33),
            control1: CGPoint(x: center.x - radius * 1.00, y: center.y + radius * 0.15),
            control2: CGPoint(x: center.x - radius * 0.98, y: center.y - radius * 0.12)
        )
        path.addLine(to: CGPoint(x: center.x - radius * 0.84, y: center.y - radius * 1.02))
        path.addQuadCurve(
            to: CGPoint(x: center.x - radius * 0.32, y: center.y - radius * 0.69),
            control: CGPoint(x: center.x - radius * 0.52, y: center.y - radius * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: center.x + radius * 0.32, y: center.y - radius * 0.69),
            control1: CGPoint(x: center.x - radius * 0.12, y: center.y - radius * 0.58),
            control2: CGPoint(x: center.x + radius * 0.12, y: center.y - radius * 0.58)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x + radius * 0.84, y: center.y - radius * 1.02),
            control: CGPoint(x: center.x + radius * 0.52, y: center.y - radius * 0.88)
        )
        path.addLine(to: CGPoint(x: center.x + radius * 0.88, y: center.y - radius * 0.33))
        path.addCurve(
            to: CGPoint(x: center.x + radius * 0.76, y: center.y + radius * 0.44),
            control1: CGPoint(x: center.x + radius * 0.98, y: center.y - radius * 0.12),
            control2: CGPoint(x: center.x + radius * 1.00, y: center.y + radius * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: center.x - radius * 0.76, y: center.y + radius * 0.44),
            control1: CGPoint(x: center.x + radius * 0.47, y: center.y + radius * 0.99),
            control2: CGPoint(x: center.x - radius * 0.47, y: center.y + radius * 0.99)
        )
        path.closeSubpath()
        return path
    }

    private static func innerEarPath(center: CGPoint, radius: CGFloat, side: Double) -> Path {
        let sign = CGFloat(side)
        var path = Path()
        path.move(to: CGPoint(x: center.x + sign * radius * 0.68, y: center.y - radius * 0.64))
        path.addLine(to: CGPoint(x: center.x + sign * radius * 0.77, y: center.y - radius * 0.88))
        path.addQuadCurve(
            to: CGPoint(x: center.x + sign * radius * 0.48, y: center.y - radius * 0.71),
            control: CGPoint(x: center.x + sign * radius * 0.59, y: center.y - radius * 0.79)
        )
        path.closeSubpath()
        return path
    }

    private static func closedEyePath(center: CGPoint, radius: CGFloat, happy: Bool) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x - radius, y: center.y))
        path.addQuadCurve(
            to: CGPoint(x: center.x + radius, y: center.y),
            control: CGPoint(x: center.x, y: center.y + radius * (happy ? 1.22 : 0.72))
        )
        return path
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
