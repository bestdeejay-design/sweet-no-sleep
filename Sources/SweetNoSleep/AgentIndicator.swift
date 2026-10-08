import SwiftUI

/// What the chest badge light communicates about the local agent bridge.
enum AgentLightState: Equatable, Sendable {
    /// No active agent session (or the indicator is turned off in Settings).
    case off
    /// At least one agent session is running.
    case working
    /// At least one agent session asked a question and waits for the user.
    case waiting
}

/// Draws the shared agent-awareness details: the chest badge light, the active
/// session count, and the waiting glyphs. Both the procedural cat and sprite
/// characters use exactly these primitives, so agent state looks identical on
/// every character.
enum AgentIndicator {
    static let workingColor = Color(hex: 0x7ED18A)
    static let waitingColor = Color(hex: 0xE5A93C)
    static let paleFill = Color(hex: 0xF5EFCF)

    /// Chest badge light plus the optional session count, drawn under the pet.
    ///
    /// - Parameters:
    ///   - center: Badge center in canvas coordinates.
    ///   - radius: Pet radius used by the renderer as the scale unit.
    ///   - animated: False under Reduce Motion or with animations disabled; the
    ///     light then renders as a static dot at a constant opacity.
    static func drawBadge(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        palette: PetPalette,
        light: AgentLightState,
        count: Int,
        animated: Bool,
        time: Double
    ) {
        guard light != .off else { return }
        let badgeRadius = max(radius * 0.20, 3)
        let isWaiting = light == .waiting
        let tint = isWaiting ? waitingColor : workingColor

        // Static ring: stays readable at 45 pt and with animations off.
        let ring = CGRect(
            x: center.x - badgeRadius,
            y: center.y - badgeRadius,
            width: badgeRadius * 2,
            height: badgeRadius * 2
        )
        context.fill(Path(ellipseIn: ring), with: .color(paleFill.opacity(0.94)))
        context.stroke(
            Path(ellipseIn: ring),
            with: .color(palette.outline.opacity(0.82)),
            style: StrokeStyle(lineWidth: max(radius * 0.026, 1))
        )

        // Double stroke while the agent waits: an attention cue that does not
        // depend on motion.
        if isWaiting {
            let outer = ring.insetBy(dx: -badgeRadius * 0.34, dy: -badgeRadius * 0.34)
            context.stroke(
                Path(ellipseIn: outer),
                with: .color(waitingColor.opacity(0.92)),
                style: StrokeStyle(lineWidth: max(radius * 0.045, 1.4))
            )
        }

        // Pulsing core, synced to a calm 24 fps timeline; static when motion is off.
        let pulse: Double = animated ? 0.65 + 0.35 * (0.5 + 0.5 * sin(time * 2.8)) : 0.85
        let coreRadius = badgeRadius * 0.58
        let core = CGRect(
            x: center.x - coreRadius,
            y: center.y - coreRadius,
            width: coreRadius * 2,
            height: coreRadius * 2
        )
        context.fill(Path(ellipseIn: core), with: .color(tint.opacity(pulse)))

        guard count > 0 else { return }
        drawSessionCount(
            in: &context,
            center: center,
            count: count,
            tint: tint,
            badgeRadius: badgeRadius,
            palette: palette
        )
    }

    /// Session count under the badge: one pip per active session.
    ///
    /// Filled dots stay legible at the 45 pt minimum pet size, where a numeral
    /// blurs into a smudge on the chest; counts above `maxPips` switch to the
    /// capped `5+` form so the row can never grow past the pet's body. The row
    /// sits below the face, so it never covers the eyes.
    static func drawSessionCount(
        in context: inout GraphicsContext,
        center: CGPoint,
        count: Int,
        tint: Color,
        badgeRadius: CGFloat,
        palette: PetPalette
    ) {
        guard count > 0 else { return }
        let shown = min(count, maxPips)
        let diameter = max(badgeRadius * 0.62, 5)
        let gap = max(badgeRadius * 0.20, 1.8)
        let plusWidth: CGFloat = count > maxPips ? gap + diameter * 0.9 : 0
        let totalWidth = diameter * CGFloat(shown) + gap * CGFloat(shown - 1) + plusWidth
        let centerY = center.y + badgeRadius + gap + diameter / 2

        var cursor = center.x - totalWidth / 2 + diameter / 2
        for _ in 0..<shown {
            let rect = CGRect(
                x: cursor - diameter / 2,
                y: centerY - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.95)))
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(palette.outline.opacity(0.88)),
                style: StrokeStyle(lineWidth: max(badgeRadius * 0.055, 0.8))
            )
            cursor += diameter + gap
        }

        guard count > maxPips else { return }
        // More than `maxPips` sessions: a small plus after the row, sized to it.
        let strokeWidth = max(diameter * 0.28, 1.2)
        let arm = diameter * 0.42
        let plusCenter = CGPoint(x: cursor - gap + plusWidth / 2, y: centerY)
        var plus = Path()
        plus.move(to: CGPoint(x: plusCenter.x - arm, y: plusCenter.y))
        plus.addLine(to: CGPoint(x: plusCenter.x + arm, y: plusCenter.y))
        plus.move(to: CGPoint(x: plusCenter.x, y: plusCenter.y - arm))
        plus.addLine(to: CGPoint(x: plusCenter.x, y: plusCenter.y + arm))
        context.stroke(
            plus,
            with: .color(palette.outline.opacity(0.92)),
            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
        )
    }

    /// Sessions above this count use the capped `+` form instead of more pips.
    static let maxPips = 5

    /// Where the attention glyph floats on the canvas: centered above the pet's
    /// head and fully inside the top of the canvas, so nothing is clipped at the
    /// 45 pt minimum size. Both renderers use this, so the cue looks the same on
    /// every character.
    static func attentionGlyphCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.105)
    }

    /// Height of the glyph box, which is also the glyph's visual height.
    static func attentionGlyphHeight(in size: CGSize) -> CGFloat {
        min(size.width, size.height) * 0.16
    }

    /// An attention mark: one stroked path plus a dot, drawn white first and
    /// amber on top. The double stroke is a static cue: it stays readable with
    /// animations off and on both light and dark desktops.
    struct AttentionGlyph {
        var stroke: Path
        var dotCenter: CGPoint
        var dotRadius: CGFloat
    }

    /// Geometry of `?` and `!`. `height` is the visual height of the finished
    /// glyph, including its strokes.
    static func glyph(_ symbol: AttentionSymbol, center: CGPoint, height: CGFloat) -> AttentionGlyph {
        switch symbol {
        case .question:
            var path = Path()
            path.move(to: CGPoint(x: center.x - height * 0.21, y: center.y - height * 0.24))
            path.addQuadCurve(
                to: CGPoint(x: center.x + height * 0.21, y: center.y - height * 0.24),
                control: CGPoint(x: center.x, y: center.y - height * 0.50)
            )
            path.addLine(to: CGPoint(x: center.x + height * 0.21, y: center.y - height * 0.06))
            path.addLine(to: CGPoint(x: center.x, y: center.y + height * 0.10))
            return AttentionGlyph(
                stroke: path,
                dotCenter: CGPoint(x: center.x, y: center.y + height * 0.36),
                dotRadius: height * 0.085
            )
        case .exclamation:
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: center.y - height * 0.44))
            path.addLine(to: CGPoint(x: center.x, y: center.y + height * 0.16))
            return AttentionGlyph(
                stroke: path,
                dotCenter: CGPoint(x: center.x, y: center.y + height * 0.42),
                dotRadius: height * 0.085
            )
        }
    }

    /// `?` / `!` inside an amber halo. Drawn white first and amber on top, so
    /// the mark keeps its shape with animations off.
    static func drawGlyphBadge(in context: inout GraphicsContext, center: CGPoint, height: CGFloat, symbol: AttentionSymbol = .question) {
        let haloRadius = height * 0.46
        let halo = CGRect(
            x: center.x - haloRadius,
            y: center.y - haloRadius * 0.98,
            width: haloRadius * 2,
            height: haloRadius * 2
        )
        context.fill(Path(ellipseIn: halo), with: .color(waitingColor.opacity(0.22)))
        context.stroke(
            Path(ellipseIn: halo),
            with: .color(waitingColor.opacity(0.85)),
            style: StrokeStyle(lineWidth: max(height * 0.062, 1))
        )

        let mark = glyph(symbol, center: center, height: height)
        let outerWidth = max(height * 0.21, 1.6)
        let coreWidth = max(height * 0.12, 1.0)
        context.stroke(
            mark.stroke,
            with: .color(.white.opacity(0.96)),
            style: StrokeStyle(lineWidth: outerWidth, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            mark.stroke,
            with: .color(waitingColor),
            style: StrokeStyle(lineWidth: coreWidth, lineCap: .round, lineJoin: .round)
        )

        let outerDot = mark.dotRadius + (outerWidth - coreWidth) / 2
        context.fill(
            Path(ellipseIn: CGRect(
                x: mark.dotCenter.x - outerDot,
                y: mark.dotCenter.y - outerDot,
                width: outerDot * 2,
                height: outerDot * 2
            )),
            with: .color(.white.opacity(0.96))
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: mark.dotCenter.x - mark.dotRadius,
                y: mark.dotCenter.y - mark.dotRadius,
                width: mark.dotRadius * 2,
                height: mark.dotRadius * 2
            )),
            with: .color(waitingColor)
        )
    }
}

enum AttentionSymbol {
    case question
    case exclamation
}
