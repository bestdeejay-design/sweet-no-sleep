import SwiftUI
import AppKit

// Breathing / blinking circle pet ("Kiwi") rendered with Canvas.
// Reuses the canonical KiwiBrain from KiwiBrain.swift (no local stub:
// PetState lives as KiwiBrain.PetState to avoid duplicate definitions).
struct KiwiCircleView: View {
    @ObservedObject var brain: KiwiBrain

    // Overall pet diameter in points. Matches SettingsView pet size.
    var diameter: CGFloat = 120

    @State private var dragStart: CGPoint?
    @State private var reactedAt: Double = 0 // last poke time, drives squash spring-back

    // Beige fur color, approx #E8C48A.
    private static let fur = Color(red: 0xE8 / 255.0, green: 0xC4 / 255.0, blue: 0x8A / 255.0)
    // Eye green, approx #8BC34A.
    private static let eyeGreen = Color(red: 0x8B / 255.0, green: 0xC3 / 255.0, blue: 0x4A / 255.0)
    // Darker fur outline, approx #6B4A2F.
    private static let outline = Color(red: 0x6B / 255.0, green: 0x4A / 255.0, blue: 0x2F / 255.0)
    // Lighter green for the heart middle layer, approx #AED581.
    private static let heartLight = Color(red: 0xAE / 255.0, green: 0xD5 / 255.0, blue: 0x81 / 255.0)

    // Breathing cycle length in seconds (sine 1.0 -> 1.04).
    private static let breathPeriod: Double = 2.4
    // Blink schedule: one 0.12s blink every ~3.7s.
    private static let blinkPeriod: Double = 3.7
    private static let blinkDuration: Double = 0.12
    // Max pupil travel in points.
    private static let pupilRange: CGFloat = 4
    // Tail wag period in seconds, amplitude in radians (6 deg).
    private static let tailPeriod: Double = 3.0
    private static let tailAmplitude: Double = 6.0 * .pi / 180.0
    private static let pokeTapDistance: CGFloat = 6 // below this, a drag end counts as a tap
    // Reaction length in seconds; mirrors the KiwiBrain poke timer.
    private static let reactDuration: Double = 0.9
    // Ear back-tilt while dragged, approx 8 degrees.
    private static let earBackTilt: CGFloat = 0.14

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let breath = Self.breathScale(at: now)
            let lidScale = Self.lidScaleY(at: now)
            let pupil = Self.pupilOffset()
            let isReacting = brain.state == .reacting
            let isDragged = brain.state == .dragged
            // 0 right after a poke, eases to 1 when the reaction ends.
            let reactT = Self.reactProgress(now: now, reactedAt: reactedAt)
            let ease = 1.0 - pow(1.0 - reactT, 3.0)
            // Squash on poke (springs back), stretch while dragged.
            let scaleX: CGFloat = isReacting ? CGFloat(1.08 - 0.08 * ease) : (isDragged ? 0.98 : 1)
            let scaleY: CGFloat = isReacting ? CGFloat(0.88 + 0.12 * ease) : (isDragged ? 1.06 : 1)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let baseRadius = min(size.width, size.height) / 2 * breath
                let rx = baseRadius * scaleX
                let ry = baseRadius * scaleY
                // Tail: tapered curve on the right, drawn behind the body.
                let tail = Self.tailPath(center: center, radius: baseRadius, time: now, lifted: isDragged)
                context.fill(tail, with: .color(Self.fur))
                context.stroke(tail, with: .color(Self.outline), lineWidth: max(baseRadius * 0.03, 1))
                // Body: beige circle, squashed or stretched by interaction.
                let bodyRect = CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
                context.fill(Path(ellipseIn: bodyRect), with: .color(Self.fur))
                // Ears: two triangles on top, tilted back while dragged.
                let lean: CGFloat = isDragged ? Self.earBackTilt : 0
                for side in [-1.0, 1.0] {
                    let outer = Self.earPath(center: center, radius: ry, side: side, inner: false, lean: lean)
                    context.fill(outer, with: .color(Self.fur))
                    context.stroke(outer, with: .color(Self.outline), lineWidth: max(baseRadius * 0.03, 1))
                    context.fill(Self.earPath(center: center, radius: ry, side: side, inner: true, lean: lean), with: .color(.white))
                }
                // Eyes: happy arcs while reacting, ellipses otherwise.
                let eyeRadius = baseRadius * 0.16
                let eyeGap = rx * 0.38
                let eyeHeight = ry * 0.30
                for side in [-1.0, 1.0] {
                    let eyeCenter = CGPoint(
                        x: center.x + CGFloat(side) * eyeGap + pupil.x,
                        y: center.y - eyeHeight + pupil.y
                    )
                    if isReacting {
                        context.stroke(
                            Self.happyEyePath(center: eyeCenter, radius: eyeRadius),
                            with: .color(Self.outline),
                            style: StrokeStyle(lineWidth: max(eyeRadius * 0.32, 2), lineCap: .round)
                        )
                        continue
                    }
                    let eyeRect = CGRect(
                        x: eyeCenter.x - eyeRadius,
                        y: eyeCenter.y - eyeRadius * lidScale,
                        width: eyeRadius * 2,
                        height: eyeRadius * 2 * max(lidScale, 0.08)
                    )
                    context.fill(Path(ellipseIn: eyeRect), with: .color(Self.eyeGreen))
                    // Pupil: small dark dot following the mouse.
                    let pupilRadius = eyeRadius * 0.38
                    let pupilRect = CGRect(
                        x: eyeCenter.x - pupilRadius + pupil.x * 0.5,
                        y: eyeCenter.y - pupilRadius + pupil.y * 0.5,
                        width: pupilRadius * 2,
                        height: pupilRadius * 2 * max(lidScale, 0.08)
                    )
                    context.fill(Path(ellipseIn: pupilRect), with: .color(.black))
                }
                // Kiwi-heart on the chest, popping bigger with a tilt on poke.
                let heartBoost: CGFloat = isReacting ? CGFloat(1.0 - ease) : 0
                let heartScale = (1.0 + (breath - 1.0) * 2.0) * (1.0 + 0.35 * heartBoost)
                let heartCenter = CGPoint(x: center.x, y: center.y + ry * 0.42)
                let heartSize = baseRadius * 0.30 * heartScale
                if heartBoost > 0.001 {
                    var tilted = context
                    tilted.translateBy(x: heartCenter.x, y: heartCenter.y)
                    tilted.rotate(by: .degrees(8 * Double(heartBoost)))
                    tilted.translateBy(x: -heartCenter.x, y: -heartCenter.y)
                    Self.paintHeart(into: &tilted, center: heartCenter, size: heartSize)
                } else {
                    var plain = context
                    Self.paintHeart(into: &plain, center: heartCenter, size: heartSize)
                }
            }
            .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .onTapGesture {
            reactedAt = Date.now.timeIntervalSinceReferenceDate
            brain.poke()
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = brain.position
                    }
                    let origin = dragStart ?? .zero
                    brain.position = CGPoint(
                        x: origin.x + value.translation.width,
                        y: origin.y + value.translation.height
                    )
                    if brain.state != .dragged {
                        brain.beginDrag()
                    }
                }
                .onEnded { value in
                    dragStart = nil
                    let d = value.translation
                    let travel = (d.width * d.width + d.height * d.height).squareRoot()
                    if travel < Self.pokeTapDistance {
                        reactedAt = Date.now.timeIntervalSinceReferenceDate
                        brain.poke()
                    } else {
                        brain.endDrag()
                    }
                }
        )
    }

    // Outer (or white inner) ear triangle; lean shifts the apex outward.
    static func earPath(center: CGPoint, radius: CGFloat, side: Double, inner: Bool, lean: CGFloat = 0) -> Path {
        let s = CGFloat(side)
        let baseY = center.y - radius * 0.62
        let baseHalf = inner ? radius * 0.13 : radius * 0.24
        let baseX = center.x + s * radius * 0.55
        let apex = CGPoint(x: center.x + s * (radius * (inner ? 0.62 : 0.72) + lean * radius), y: center.y - radius * (inner ? 0.98 : 1.10))
        var path = Path()
        path.move(to: CGPoint(x: baseX - baseHalf, y: baseY))
        path.addLine(to: apex)
        path.addLine(to: CGPoint(x: baseX + baseHalf, y: baseY))
        path.closeSubpath()
        return path
    }

    // Tapered tail on the right side, wagging; lifted points up while dragged.
    static func tailPath(center: CGPoint, radius: CGFloat, time: Double, lifted: Bool = false) -> Path {
        let wag = sin(2.0 * .pi * time / tailPeriod) * tailAmplitude
        let lift: Double = lifted ? -0.45 : 0
        let dir = CGVector(dx: cos(wag), dy: sin(wag) - 0.35 + lift)
        let base = CGPoint(x: center.x + radius * 0.82, y: center.y + radius * 0.25)
        let length = radius * 0.75
        let tip = CGPoint(x: base.x + dir.dx * length, y: base.y + dir.dy * length)
        let inv = 1.0 / max(sqrt(dir.dx * dir.dx + dir.dy * dir.dy), 0.001)
        let perp = CGVector(dx: -dir.dy * inv, dy: dir.dx * inv)
        let baseHalf = radius * 0.11
        let tipHalf = radius * 0.03
        let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2 - radius * 0.08)
        var path = Path()
        path.move(to: CGPoint(x: base.x + perp.dx * baseHalf, y: base.y + perp.dy * baseHalf))
        path.addQuadCurve(to: CGPoint(x: tip.x + perp.dx * tipHalf, y: tip.y + perp.dy * tipHalf), control: mid)
        path.addLine(to: CGPoint(x: tip.x - perp.dx * tipHalf, y: tip.y - perp.dy * tipHalf))
        path.addQuadCurve(to: CGPoint(x: base.x - perp.dx * baseHalf, y: base.y - perp.dy * baseHalf), control: mid)
        path.closeSubpath()
        return path
    }

    // Happy closed eye: small arch stroked with a round cap.
    static func happyEyePath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x - radius, y: center.y + radius * 0.25))
        path.addQuadCurve(
            to: CGPoint(x: center.x + radius, y: center.y + radius * 0.25),
            control: CGPoint(x: center.x, y: center.y - radius * 1.5)
        )
        return path
    }

    // Three-layer heart fill shared by the normal and tilted passes.
    static func paintHeart(into context: inout GraphicsContext, center: CGPoint, size: CGFloat) {
        context.fill(Self.heartPath(center: center, size: size), with: .color(Self.eyeGreen))
        context.fill(Self.heartPath(center: center, size: size * 0.68), with: .color(Self.heartLight))
        context.fill(Self.heartPath(center: center, size: size * 0.38), with: .color(.white))
    }

    // Symmetric heart shape centered at the given point.
    static func heartPath(center: CGPoint, size s: CGFloat) -> Path {
        let cx = center.x
        let cy = center.y
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy + s * 0.9))
        path.addCurve(
            to: CGPoint(x: cx - s, y: cy - s * 0.1),
            control1: CGPoint(x: cx - s * 1.2, y: cy + s * 0.4),
            control2: CGPoint(x: cx - s, y: cy + s * 0.4)
        )
        path.addCurve(
            to: CGPoint(x: cx - s * 0.5, y: cy - s * 0.6),
            control1: CGPoint(x: cx - s, y: cy - s * 0.55),
            control2: CGPoint(x: cx - s * 0.85, y: cy - s * 0.75)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: cy - s * 0.25),
            control1: CGPoint(x: cx - s * 0.25, y: cy - s * 0.5),
            control2: CGPoint(x: cx - s * 0.1, y: cy - s * 0.25)
        )
        path.addCurve(
            to: CGPoint(x: cx + s * 0.5, y: cy - s * 0.6),
            control1: CGPoint(x: cx + s * 0.1, y: cy - s * 0.25),
            control2: CGPoint(x: cx + s * 0.25, y: cy - s * 0.5)
        )
        path.addCurve(
            to: CGPoint(x: cx + s, y: cy - s * 0.1),
            control1: CGPoint(x: cx + s * 0.85, y: cy - s * 0.75),
            control2: CGPoint(x: cx + s, y: cy - s * 0.55)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: cy + s * 0.9),
            control1: CGPoint(x: cx + s, y: cy + s * 0.4),
            control2: CGPoint(x: cx + s * 1.2, y: cy + s * 0.4)
        )
        path.closeSubpath()
        return path
    }

    // Reaction progress from a poke timestamp: 0 fresh, 1 after reactDuration.
    static func reactProgress(now: Double, reactedAt: Double) -> Double {
        guard reactedAt > 0 else { return 1 }
        return min(max((now - reactedAt) / reactDuration, 0), 1)
    }

    // Sine breathing scale between 1.0 and 1.04 over breathPeriod.
    static func breathScale(at time: Double) -> CGFloat {
        let phase = sin(2.0 * .pi * time / breathPeriod)
        return CGFloat(1.02 + 0.02 * phase)
    }

    // Vertical eye scale: collapses to near zero during the blink window.
    static func lidScaleY(at time: Double) -> CGFloat {
        let phase = time.truncatingRemainder(dividingBy: blinkPeriod)
        if phase < 0 || phase > blinkPeriod {
            return 1.0
        }
        return phase < blinkDuration ? 0.1 : 1.0
    }

    // Pupil offset from global mouse location, clamped to pupilRange.
    static func pupilOffset() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.main else {
            return .zero
        }
        let frame = screen.frame
        let halfW = max(frame.width / 2, 1)
        let halfH = max(frame.height / 2, 1)
        let normX = CGFloat((mouse.x - frame.midX) / halfW)
        let normY = CGFloat((mouse.y - frame.midY) / halfH)
        let clampedX = min(max(normX, -1), 1) * pupilRange
        let clampedY = min(max(normY, -1), 1) * pupilRange
        return CGPoint(x: clampedX, y: clampedY)
    }
}
