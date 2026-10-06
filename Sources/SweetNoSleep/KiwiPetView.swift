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

    private var petSide: CGFloat { CGFloat(model.petSize) + 48 }
    private var panelWidth: CGFloat { model.isBreakDue ? max(petSide, PetBreakReminderBubble.width) : petSide }
    private var panelHeight: CGFloat { petSide + (model.isBreakDue ? PetBreakReminderBubble.height : 0) }

    var body: some View {
        VStack(spacing: 0) {
            if model.isBreakDue {
                PetBreakReminderBubble(model: model)
            }
            KiwiPetView(model: model, onDragChanged: onDragChanged, onDragEnded: onDragEnded)
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .background(Color.clear)
    }
}

struct PetBreakReminderBubble: View {
    static let width: CGFloat = 228
    static let height: CGFloat = 88

    @ObservedObject var model: SweetNoSleepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "eye.circle.fill")
                    .foregroundStyle(Color(hex: 0x5EAC70))
                Text("Короткая пауза")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            Text("Отведите взгляд от кода и посмотрите вдаль около 20 секунд.")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            HStack(spacing: 6) {
                Button("Позже · 5 мин") {
                    model.dismissBreakReminder(snoozeMinutes: 5)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 9, weight: .medium, design: .rounded))

                Spacer(minLength: 0)

                Button("Пауза сделана") {
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

    private var renderedSize: CGFloat {
        sizeOverride ?? CGFloat(model.petSize)
    }

    private var canvasSize: CGFloat { renderedSize + 48 }
    private var reduceMotion: Bool { systemReduceMotion || !model.animationsEnabled }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 0.12 : 1.0 / 24.0,
                paused: !model.isPetVisible
            )
        ) { timeline in
            Canvas { context, size in
                Self.drawPet(
                    in: &context,
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    mood: model.mood,
                    palette: .palette(for: model.activeSkin),
                    gaze: tracksCursor ? cursorGaze(canvasSize: canvasSize, topInset: model.isBreakDue ? PetBreakReminderBubble.height : 0) : .zero,
                    reducedMotion: reduceMotion
                )
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
        .accessibilityLabel("Киви, питомец Sweet No Sleep")
        .accessibilityHint(allowsDragging ? "Нажмите, чтобы поздороваться, или перетащите питомца." : "Нажмите, чтобы поздороваться.")
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
        reducedMotion: Bool
    ) {
        let radius = min(size.width, size.height) * 0.335
        let center = CGPoint(x: size.width * 0.50, y: size.height * 0.55)
        let headCenter = CGPoint(x: center.x, y: center.y - radius * 0.23)
        let profile = palette.animation
        let isDancing = mood == .dancing && !reducedMotion
        let isStretching = mood == .stretching
        let danceSway = isDancing ? CGFloat(sin(time * 6.2)) * radius * 0.055 : 0
        let danceBounce = isDancing ? CGFloat(abs(sin(time * 6.2))) * radius * 0.075 : 0
        let stretchLift = isStretching ? radius * 0.035 : 0
        let breath: CGFloat = reducedMotion ? 0 : CGFloat(sin(time * profile.breathingFrequency)) * CGFloat(profile.breathingAmplitude)
        let bob: CGFloat = reducedMotion ? 0 : CGFloat(sin(time * 1.45)) * radius * 0.018
        let bodyCenter = CGPoint(x: center.x + danceSway, y: center.y + bob - danceBounce)
        let headBob = CGPoint(x: headCenter.x + danceSway * 0.32, y: headCenter.y + bob - danceBounce * 0.42 - stretchLift)
        let posedBreath = breath + (isStretching ? 0.045 : 0)

        if mood == .working || mood == .celebrating || mood == .dancing || mood == .breakReminder {
            let haloRect = CGRect(
                x: center.x - radius * 1.16,
                y: center.y - radius * 0.98,
                width: radius * 2.32,
                height: radius * 2.32
            )
            let haloOpacity = mood == .celebrating || mood == .dancing ? 0.15 : (mood == .breakReminder ? 0.13 : 0.08)
            context.fill(Path(ellipseIn: haloRect), with: .color(palette.accent.opacity(haloOpacity)))
        }

        drawTail(in: &context, center: bodyCenter, radius: radius, time: time, palette: palette, mood: mood, reducedMotion: reducedMotion)
        drawBody(in: &context, center: bodyCenter, radius: radius, palette: palette, breath: posedBreath)
        drawHead(in: &context, center: headBob, radius: radius, palette: palette, breath: posedBreath)
        drawFace(in: &context, center: headBob, radius: radius, time: time, palette: palette, mood: mood, gaze: gaze, reducedMotion: reducedMotion)
        drawPaws(in: &context, center: bodyCenter, radius: radius, palette: palette, time: time, mood: mood, reducedMotion: reducedMotion)
        drawKiwiBadge(in: &context, center: CGPoint(x: center.x + danceSway * 0.45, y: center.y + radius * 0.40 + bob - danceBounce), radius: radius, palette: palette, time: time, mood: mood, reducedMotion: reducedMotion)

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
        if mood == .curious || mood == .breakReminder {
            let sparkle = CGPoint(x: center.x + radius * 0.83, y: center.y - radius * 0.82)
            context.fill(starPath(center: sparkle, outerRadius: radius * 0.11, innerRadius: radius * 0.045), with: .color(palette.accent.opacity(0.90)))
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
        drawLeaf(in: &context, from: leafBase, to: CGPoint(x: center.x - radius * 0.17, y: center.y - radius * 1.00), radius: radius * 0.105, color: palette.accent)
        drawLeaf(in: &context, from: leafBase, to: CGPoint(x: center.x + radius * 0.16, y: center.y - radius * 1.02), radius: radius * 0.105, color: palette.accent.opacity(0.9))
        drawLeaf(in: &context, from: leafBase, to: CGPoint(x: center.x, y: center.y - radius * 1.08), radius: radius * 0.11, color: palette.accent)
    }

    private static func drawFace(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double, palette: PetPalette, mood: KiwiMood, gaze: CGPoint, reducedMotion: Bool) {
        let isHappy = mood == .celebrating || mood == .dancing
        let isResting = mood == .resting || mood == .stretching
        let eyesWide = mood == .curious || mood == .breakReminder
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
        let step: CGFloat = isMoving && !reducedMotion ? CGFloat(sin(time * (mood == .dancing ? 6.2 : 8))) * radius * 0.065 : 0
        let lift: CGFloat = reducedMotion ? 0 : (mood == .stretching ? radius * 0.11 : (mood == .dancing ? CGFloat(abs(sin(time * 6.2))) * radius * 0.12 : 0))
        for (index, side) in [-1.0, 1.0].enumerated() {
            let offset = index == 0 ? step : -step
            let paw = CGRect(
                x: center.x + CGFloat(side) * radius * 0.30 - radius * 0.20,
                y: center.y + radius * 0.70 + offset - lift,
                width: radius * 0.40,
                height: radius * 0.20
            )
            context.fill(Path(ellipseIn: paw), with: .color(palette.furLight))
            context.stroke(Path(ellipseIn: paw), with: .color(palette.outline.opacity(0.75)), style: StrokeStyle(lineWidth: max(radius * 0.025, 0.9)))
        }
    }

    private static func drawKiwiBadge(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, palette: PetPalette, time: Double, mood: KiwiMood, reducedMotion: Bool) {
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

    private static func drawCelebrationEffect(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        palette: PetPalette,
        effect: PetCelebrationEffect,
        reducedMotion: Bool
    ) {
        let twinkle = reducedMotion ? 0.86 : CGFloat(0.72 + (sin(time * 7) + 1) * 0.14)
        switch effect {
        case .leaves:
            let drift = reducedMotion ? 0 : CGFloat(sin(time * 4)) * radius * 0.035
            drawLeaf(
                in: &context,
                from: CGPoint(x: center.x - radius * 0.84, y: center.y - radius * 0.24 + drift),
                to: CGPoint(x: center.x - radius * 1.03, y: center.y - radius * 0.63 + drift),
                radius: radius * 0.14,
                color: palette.accent.opacity(0.92)
            )
            drawLeaf(
                in: &context,
                from: CGPoint(x: center.x + radius * 0.82, y: center.y - radius * 0.18 - drift),
                to: CGPoint(x: center.x + radius * 1.02, y: center.y - radius * 0.57 - drift),
                radius: radius * 0.13,
                color: palette.accent.opacity(0.78)
            )
        case .moonDust:
            let moonCenter = CGPoint(x: center.x + radius * 0.98, y: center.y - radius * 0.42)
            context.fill(crescentPath(center: moonCenter, radius: radius * 0.17), with: .color(palette.accent.opacity(0.92)))
            let stars: [(CGFloat, CGFloat, CGFloat)] = [(-0.95, -0.45, 0.09), (0.68, -0.73, 0.08), (-0.82, 0.20, 0.065)]
            for (x, y, scale) in stars {
                let point = CGPoint(x: center.x + x * radius, y: center.y + y * radius)
                context.fill(starPath(center: point, outerRadius: radius * scale * twinkle, innerRadius: radius * scale * 0.30), with: .color(palette.furLight))
            }
        case .berryHearts:
            let hearts: [(CGFloat, CGFloat, CGFloat)] = [(-0.98, -0.42, 0.13), (0.98, -0.55, 0.16), (-0.89, 0.24, 0.10)]
            for (x, y, scale) in hearts {
                let point = CGPoint(x: center.x + x * radius, y: center.y + y * radius)
                context.fill(heartPath(center: point, size: radius * scale * twinkle), with: .color(palette.cheek.opacity(0.92)))
            }
        case .starburst:
            let stars: [(CGFloat, CGFloat, CGFloat)] = [(-1.00, -0.48, 0.11), (0.98, -0.53, 0.14), (-0.94, 0.25, 0.085), (0.88, 0.28, 0.09)]
            for (x, y, scale) in stars {
                let point = CGPoint(x: center.x + x * radius, y: center.y + y * radius)
                context.fill(starPath(center: point, outerRadius: radius * scale * twinkle, innerRadius: radius * scale * 0.32), with: .color(palette.accent))
            }
        }
    }

    private static func heartPath(center: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y + size * 0.78))
        path.addCurve(
            to: CGPoint(x: center.x - size, y: center.y - size * 0.08),
            control1: CGPoint(x: center.x - size * 1.15, y: center.y + size * 0.40),
            control2: CGPoint(x: center.x - size, y: center.y + size * 0.33)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y - size * 0.18),
            control1: CGPoint(x: center.x - size * 0.90, y: center.y - size * 0.70),
            control2: CGPoint(x: center.x - size * 0.25, y: center.y - size * 0.82)
        )
        path.addCurve(
            to: CGPoint(x: center.x + size, y: center.y - size * 0.08),
            control1: CGPoint(x: center.x + size * 0.25, y: center.y - size * 0.82),
            control2: CGPoint(x: center.x + size * 0.90, y: center.y - size * 0.70)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y + size * 0.78),
            control1: CGPoint(x: center.x + size, y: center.y + size * 0.33),
            control2: CGPoint(x: center.x + size * 1.15, y: center.y + size * 0.40)
        )
        path.closeSubpath()
        return path
    }

    private static func crescentPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y + radius),
            control: CGPoint(x: center.x + radius * 1.35, y: center.y)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - radius),
            control: CGPoint(x: center.x - radius * 0.30, y: center.y + radius * 0.15)
        )
        path.closeSubpath()
        return path
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

    private static func drawLeaf(in context: inout GraphicsContext, from start: CGPoint, to end: CGPoint, radius: CGFloat, color: Color) {
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        var leaf = Path()
        leaf.move(to: start)
        leaf.addQuadCurve(to: end, control: CGPoint(x: midpoint.x - radius * 0.42, y: midpoint.y))
        leaf.addQuadCurve(to: start, control: CGPoint(x: midpoint.x + radius * 0.42, y: midpoint.y + radius * 0.25))
        context.fill(leaf, with: .color(color))
        var vein = Path()
        vein.move(to: start)
        vein.addLine(to: end)
        context.stroke(vein, with: .color(Color.white.opacity(0.38)), style: StrokeStyle(lineWidth: max(radius * 0.10, 0.6), lineCap: .round))
    }

    private static func starPath(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> Path {
        var path = Path()
        for point in 0..<8 {
            let angle = Double(point) * .pi / 4 - .pi / 2
            let radius = point.isMultiple(of: 2) ? outerRadius : innerRadius
            let next = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            if point == 0 { path.move(to: next) } else { path.addLine(to: next) }
        }
        path.closeSubpath()
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
