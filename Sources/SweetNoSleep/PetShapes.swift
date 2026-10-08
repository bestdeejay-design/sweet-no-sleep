import SwiftUI

/// Small decal shapes shared by the procedural cat and sprite characters:
/// sparkles, hearts, crescents, and leaves. Keeping them in one place means the
/// celebration effects look the same on every character.
enum PetShapes {
    static func star(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> Path {
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

    static func heart(center: CGPoint, size: CGFloat) -> Path {
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

    /// Plus-shaped sparkle (rounded cross).
    static func plusSpark(center: CGPoint, arm: CGFloat, thickness: CGFloat) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: center.x - arm, y: center.y - thickness / 2, width: arm * 2, height: thickness),
            cornerSize: CGSize(width: thickness / 2, height: thickness / 2)
        )
        path.addRoundedRect(
            in: CGRect(x: center.x - thickness / 2, y: center.y - arm, width: thickness, height: arm * 2),
            cornerSize: CGSize(width: thickness / 2, height: thickness / 2)
        )
        return path
    }

    static func crescent(center: CGPoint, radius: CGFloat) -> Path {
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

    static func leaf(in context: inout GraphicsContext, from start: CGPoint, to end: CGPoint, radius: CGFloat, color: Color) {
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

    /// Master opacity envelope over the ~2.0 s celebration window.
    /// Eases in over the first 20%, holds, eases out over the last 40%.
    static func celebrationAlpha(time: Double, reducedMotion: Bool) -> CGFloat {
        if reducedMotion { return 0.8 }
        let window = 2.0
        var progress = (time.truncatingRemainder(dividingBy: window)) / window
        if progress < 0 { progress += 1 }
        func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
            let clamped = min(max((x - edge0) / (edge1 - edge0), 0), 1)
            return clamped * clamped * (3 - 2 * clamped)
        }
        let fadeIn = smoothstep(0, 0.2, progress)
        let fadeOut = 1 - smoothstep(0.6, 1.0, progress)
        return CGFloat(0.9 * fadeIn * fadeOut)
    }

    /// Pulsating halo ring plus blink sparkles shared by all celebration effects.
    static func celebrationBase(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        palette: PetPalette,
        fade: CGFloat,
        reducedMotion: Bool
    ) {
        let haloPulse: CGFloat = reducedMotion ? 1.0 : 1.0 + 0.06 * CGFloat(sin(time * 5.0))
        let haloBase: CGFloat = reducedMotion ? 0.16 : 0.10 + 0.12 * CGFloat(0.5 + 0.5 * sin(time * 5.0))
        let haloRect = CGRect(
            x: center.x - radius * 1.16 * haloPulse,
            y: center.y - radius * 0.98 * haloPulse,
            width: radius * 2.32 * haloPulse,
            height: radius * 2.32 * haloPulse
        )
        context.stroke(
            Path(ellipseIn: haloRect),
            with: .color(palette.accent.opacity(min(haloBase * fade, 1.0))),
            style: StrokeStyle(lineWidth: max(radius * 0.05, 1), lineCap: .round)
        )

        let blinkers: [(CGFloat, CGFloat, Double)] = [
            (-1.12, -0.78, 0.0), (1.12, -0.82, 2.1), (-1.06, 0.44, 4.2), (1.04, 0.48, 1.05)
        ]
        for (x, y, phase) in blinkers {
            let point = CGPoint(x: center.x + x * radius, y: center.y + y * radius)
            let blink: CGFloat = reducedMotion ? 0.7 : CGFloat(pow(max(0, sin(time * 3.0 + phase)), 2.0))
            guard blink > 0.02 else { continue }
            let arm = radius * 0.09 * (reducedMotion ? 1.0 : (0.85 + 0.15 * blink))
            context.fill(
                plusSpark(center: point, arm: arm, thickness: max(arm * 0.38, 0.8)),
                with: .color(palette.furLight.opacity(min(blink * fade, 1.0)))
            )
        }
    }
}
