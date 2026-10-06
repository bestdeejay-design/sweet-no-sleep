import AppKit
import SwiftUI

enum PetCelebrationEffect {
    case leaves
    case moonDust
    case berryHearts
}

struct PetAnimationProfile {
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
    let animation: PetAnimationProfile

    static func palette(for skin: KiwiSkin) -> PetPalette {
        switch skin {
        case .kiwi:
            PetPalette(
                fur: Color(hex: 0xE8C894), furLight: Color(hex: 0xFFF0D2),
                outline: Color(hex: 0x5D443B), innerEar: Color(hex: 0xE88D85),
                iris: Color(hex: 0x5C9B73), accent: Color(hex: 0x75C56A),
                cheek: Color(hex: 0xE99B8E),
                animation: PetAnimationProfile(breathingFrequency: 2.2, breathingAmplitude: 0.018, tailFrequency: 3.0, tailAmplitude: 0.14, celebrationEffect: .leaves)
            )
        case .moonlight:
            PetPalette(
                fur: Color(hex: 0xB9B9E9), furLight: Color(hex: 0xE8E8FF),
                outline: Color(hex: 0x414268), innerEar: Color(hex: 0xD99FCB),
                iris: Color(hex: 0x6C73B5), accent: Color(hex: 0xA5A3FF),
                cheek: Color(hex: 0xD99FCB),
                animation: PetAnimationProfile(breathingFrequency: 1.8, breathingAmplitude: 0.012, tailFrequency: 1.6, tailAmplitude: 0.06, celebrationEffect: .moonDust)
            )
        case .strawberry:
            PetPalette(
                fur: Color(hex: 0xF0A6A6), furLight: Color(hex: 0xFFE1DA),
                outline: Color(hex: 0x693E4B), innerEar: Color(hex: 0xBB6986),
                iris: Color(hex: 0x659276), accent: Color(hex: 0x83C66C),
                cheek: Color(hex: 0xE77F86),
                animation: PetAnimationProfile(breathingFrequency: 2.7, breathingAmplitude: 0.022, tailFrequency: 4.0, tailAmplitude: 0.17, celebrationEffect: .berryHearts)
            )
        }
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
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?

    @State private var isDragging = false

    private var renderedSize: CGFloat {
        sizeOverride ?? CGFloat(model.petSize)
    }

    private var canvasSize: CGFloat { renderedSize + 48 }
    private var reduceMotion: Bool { systemReduceMotion || !model.animationsEnabled }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 0.8 : 1.0 / 24.0,
                paused: reduceMotion || !model.isPetVisible
            )
        ) { timeline in
            Canvas { context, size in
                Self.drawPet(
                    in: &context,
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    mood: model.mood,
                    palette: .palette(for: model.skin),
                    reducedMotion: reduceMotion
                )
            }
            .frame(width: canvasSize, height: canvasSize)
        }
        .frame(width: canvasSize, height: canvasSize)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture { model.poke() }
        .accessibilityElement()
        .accessibilityLabel("Киви, питомец Sweet No Sleep")
        .accessibilityHint(allowsDragging ? "Нажмите, чтобы поздороваться, или перетащите питомца." : "Нажмите, чтобы поздороваться.")
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
        reducedMotion: Bool
    ) {
        let radius = min(size.width, size.height) * 0.335
        let center = CGPoint(x: size.width * 0.50, y: size.height * 0.55)
        let headCenter = CGPoint(x: center.x, y: center.y - radius * 0.23)
        let profile = palette.animation
        let breath: CGFloat = reducedMotion ? 0 : CGFloat(sin(time * profile.breathingFrequency)) * CGFloat(profile.breathingAmplitude)
        let bob: CGFloat = reducedMotion ? 0 : CGFloat(sin(time * 1.45)) * radius * 0.018
        let bodyCenter = CGPoint(x: center.x, y: center.y + bob)
        let headBob = CGPoint(x: headCenter.x, y: headCenter.y + bob)

        if mood == .working || mood == .celebrating {
            let haloRect = CGRect(
                x: center.x - radius * 1.16,
                y: center.y - radius * 0.98,
                width: radius * 2.32,
                height: radius * 2.32
            )
            context.fill(Path(ellipseIn: haloRect), with: .color(palette.accent.opacity(mood == .celebrating ? 0.14 : 0.08)))
        }

        drawTail(in: &context, center: bodyCenter, radius: radius, time: time, palette: palette, mood: mood, reducedMotion: reducedMotion)
        drawBody(in: &context, center: bodyCenter, radius: radius, palette: palette, breath: breath)
        drawHead(in: &context, center: headBob, radius: radius, palette: palette, breath: breath)
        drawFace(in: &context, center: headBob, radius: radius, time: time, palette: palette, mood: mood, reducedMotion: reducedMotion)
        drawPaws(in: &context, center: bodyCenter, radius: radius, palette: palette, time: time, mood: mood, reducedMotion: reducedMotion)
        drawKiwiBadge(in: &context, center: CGPoint(x: center.x, y: center.y + radius * 0.40 + bob), radius: radius, palette: palette, time: time, mood: mood, reducedMotion: reducedMotion)

        if mood == .celebrating {
            drawCelebrationEffect(
                in: &context,
                center: center,
                radius: radius,
                time: time,
                palette: palette,
                effect: profile.celebrationEffect
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
        drawLeaf(in: &context, from: leafBase, to: CGPoint(x: center.x - radius * 0.17, y: center.y - radius * 1.00), radius: radius * 0.105, color: palette.accent)
        drawLeaf(in: &context, from: leafBase, to: CGPoint(x: center.x + radius * 0.16, y: center.y - radius * 1.02), radius: radius * 0.105, color: palette.accent.opacity(0.9))
        drawLeaf(in: &context, from: leafBase, to: CGPoint(x: center.x, y: center.y - radius * 1.08), radius: radius * 0.11, color: palette.accent)
    }

    private static func drawFace(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double, palette: PetPalette, mood: KiwiMood, reducedMotion: Bool) {
        let isHappy = mood == .celebrating
        let isResting = mood == .resting
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
                let eyeRect = CGRect(x: eyeCenter.x - eyeWidth, y: eyeCenter.y - eyeHeight * 0.52, width: eyeWidth * 2, height: eyeHeight * 1.7)
                context.fill(Path(ellipseIn: eyeRect), with: .color(palette.outline))
                let irisRect = eyeRect.insetBy(dx: eyeWidth * 0.22, dy: eyeHeight * 0.14)
                context.fill(Path(ellipseIn: irisRect), with: .color(palette.iris))
                let pupilRect = CGRect(x: eyeCenter.x - eyeWidth * 0.31, y: eyeCenter.y - eyeHeight * 0.33, width: eyeWidth * 0.62, height: eyeHeight * 0.72)
                context.fill(Path(ellipseIn: pupilRect), with: .color(Color(hex: 0x30282C)))
                let shineRect = CGRect(x: eyeCenter.x - eyeWidth * 0.22, y: eyeCenter.y - eyeHeight * 0.38, width: eyeWidth * 0.22, height: eyeWidth * 0.22)
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

        var smile = Path()
        smile.move(to: CGPoint(x: center.x, y: center.y + radius * 0.24))
        smile.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.31))
        smile.move(to: CGPoint(x: center.x, y: center.y + radius * 0.31))
        smile.addQuadCurve(to: CGPoint(x: center.x - radius * 0.12, y: center.y + radius * 0.29), control: CGPoint(x: center.x - radius * 0.07, y: center.y + radius * 0.42))
        smile.move(to: CGPoint(x: center.x, y: center.y + radius * 0.31))
        smile.addQuadCurve(to: CGPoint(x: center.x + radius * 0.12, y: center.y + radius * 0.29), control: CGPoint(x: center.x + radius * 0.07, y: center.y + radius * 0.42))
        context.stroke(smile, with: .color(palette.outline), style: StrokeStyle(lineWidth: max(radius * 0.035, 1.2), lineCap: .round))

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
        let step: CGFloat = mood == .walking && !reducedMotion ? CGFloat(sin(time * 8)) * radius * 0.045 : 0
        for (index, side) in [-1.0, 1.0].enumerated() {
            let offset = index == 0 ? step : -step
            let paw = CGRect(
                x: center.x + CGFloat(side) * radius * 0.30 - radius * 0.20,
                y: center.y + radius * 0.70 + offset,
                width: radius * 0.40,
                height: radius * 0.20
            )
            context.fill(Path(ellipseIn: paw), with: .color(palette.furLight))
            context.stroke(Path(ellipseIn: paw), with: .color(palette.outline.opacity(0.75)), style: StrokeStyle(lineWidth: max(radius * 0.025, 0.9)))
        }
    }

    private static func drawKiwiBadge(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, palette: PetPalette, time: Double, mood: KiwiMood, reducedMotion: Bool) {
        let pulse: CGFloat = mood == .working && !reducedMotion ? 1 + CGFloat(sin(time * 2.8)) * 0.035 : 1
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
        let amplitude = mood == .working ? profile.tailAmplitude : profile.tailAmplitude * 0.55
        let wag: CGFloat = reducedMotion ? 0 : CGFloat(sin(time * profile.tailFrequency)) * radius * amplitude
        let lifted = mood == .celebrating ? -radius * 0.18 : 0
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
        effect: PetCelebrationEffect
    ) {
        let twinkle = CGFloat(0.72 + (sin(time * 7) + 1) * 0.14)
        switch effect {
        case .leaves:
            let drift = CGFloat(sin(time * 4)) * radius * 0.035
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
