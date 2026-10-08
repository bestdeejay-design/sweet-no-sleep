import SwiftUI

/// Draws sprite characters (`pet.json` packs) on the same Canvas as the
/// procedural cat: the body breathes, the tail wags around its pivot, and the
/// agent-awareness details (badge light, session count, waiting glyph) come from
/// the shared `AgentIndicator`, so behavior matches Kiwi exactly.
enum SpriteCharacterRenderer {
    /// Fraction of the canvas height the sprite occupies; keeps every character
    /// at the same on-screen size as the procedural cat.
    private static let spriteHeightRatio: CGFloat = 0.88
    /// Baseline the paws rest on, matching `KiwiPetView.drawPet`.
    private static let feetRatio: CGFloat = 0.862

    static func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        mood: KiwiMood,
        palette: PetPalette,
        sprite: CharacterSprite,
        light: AgentLightState,
        agentCount: Int,
        attention: AttentionSymbol?,
        animated: Bool
    ) {
        let profile = palette.animation
        let feedBounce = mood == .working || light == .working
        let side = size.height * spriteHeightRatio
        let feet = CGPoint(x: size.width * 0.5, y: size.height * feetRatio)
        let rect = CGRect(x: feet.x - side / 2, y: feet.y - side, width: side, height: side)
        let petRadius = min(size.width, size.height) * 0.335

        let isDancing = mood == .dancing && animated
        let isCelebrating = mood == .celebrating
        let isWaiting = mood == .waitingForApproval
        let danceSway = isDancing ? CGFloat(sin(time * 6.2)) * 3.2 : 0
        let walkSway = mood == .walking && animated ? CGFloat(sin(time * 8)) * 2.0 : 0
        let lean = danceSway + walkSway + (isWaiting ? -2.4 : 0) + (mood == .curious ? 1.4 : 0)
        let hop: CGFloat = {
            guard animated else { return 0 }
            if isDancing { return CGFloat(abs(sin(time * 6.2))) * side * 0.020 }
            if isCelebrating { return CGFloat(abs(sin(time * 3.1))) * side * 0.028 }
            if feedBounce { return CGFloat(abs(sin(time * 2.4))) * side * 0.010 }
            return 0
        }()
        // A working agent makes breathing a touch quicker; that is the quiet
        // "the pet is aware of the work" cue.
        let breathFrequency = profile.breathingFrequency * (light == .working ? 1.25 : 1.0)
        let breath: CGFloat = animated ? CGFloat(sin(time * breathFrequency)) * CGFloat(profile.breathingAmplitude) : 0
        let stretch: CGFloat = (mood == .stretching && animated) ? 0.05 : 0

        drawHalo(in: &context, center: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.56), radius: side * 0.52, palette: palette, mood: mood)

        // Tail: rotation around the pivot from `pet.json`, drawn first so the
        // body's seam band covers its cut.
        let pivot = CGPoint(
            x: rect.minX + sprite.tailPivot.x * rect.width,
            y: rect.minY + sprite.tailPivot.y * rect.height
        )
        let swingScale: CGFloat = {
            if isDancing { return 2.0 }
            if isWaiting { return 1.5 }
            if mood == .working || light == .working { return 1.2 }
            if mood == .resting { return 0.5 }
            return 1.0
        }()
        let calmSwing = CGFloat(sprite.art.tailSwingDegrees)
        let baseSwing = animated ? CGFloat(sin(time * profile.tailFrequency)) * calmSwing * swingScale : 0
        let raisedLift: CGFloat = isWaiting ? -7 : (isDancing ? 8 : (feedBounce ? 3 : 0))
        let tailAngle = (baseSwing + raisedLift) * .pi / 180

        if animated {
            context.translateBy(x: 0, y: -hop)
            context.concatenate(CGAffineTransform(translationX: feet.x, y: feet.y))
            context.concatenate(CGAffineTransform(rotationAngle: lean * .pi / 180))
            context.concatenate(CGAffineTransform(translationX: -feet.x, y: -feet.y))
        }

        context.drawLayer { tailLayer in
            tailLayer.concatenate(CGAffineTransform(translationX: pivot.x, y: pivot.y))
            tailLayer.concatenate(CGAffineTransform(rotationAngle: tailAngle))
            tailLayer.concatenate(CGAffineTransform(translationX: -pivot.x, y: -pivot.y))
            tailLayer.draw(Image(decorative: sprite.tail, scale: 1), in: rect)
        }

        context.drawLayer { bodyLayer in
            bodyLayer.concatenate(CGAffineTransform(translationX: feet.x, y: feet.y))
            bodyLayer.concatenate(CGAffineTransform(scaleX: 1, y: 1 + breath * 1.6 + stretch))
            bodyLayer.concatenate(CGAffineTransform(translationX: -feet.x, y: -feet.y))
            bodyLayer.draw(Image(decorative: sprite.body, scale: 1), in: rect)
        }

        if isCelebrating || isDancing {
            drawCelebration(in: &context, center: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.5), radius: side * 0.44, time: time, palette: palette, animated: animated)
        }
        if mood == .curious || mood == .breakReminder {
            let sparkle = CGPoint(x: rect.maxX - side * 0.16, y: rect.minY + side * 0.20)
            context.fill(
                PetShapes.star(center: sparkle, outerRadius: side * 0.05, innerRadius: side * 0.021),
                with: .color(palette.accent.opacity(0.90))
            )
        }

        AgentIndicator.drawBadge(
            in: &context,
            center: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.70),
            radius: petRadius,
            palette: palette,
            light: light,
            count: agentCount,
            animated: animated,
            time: time
        )

        if let attention {
            AgentIndicator.drawGlyphBadge(
                in: &context,
                center: AgentIndicator.attentionGlyphCenter(in: size),
                height: AgentIndicator.attentionGlyphHeight(in: size),
                symbol: attention
            )
        }
    }

    private static func drawHalo(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        palette: PetPalette,
        mood: KiwiMood
    ) {
        let isWaiting = mood == .waitingForApproval
        guard mood == .working || mood == .celebrating || mood == .dancing || mood == .breakReminder || isWaiting else { return }
        let opacity: Double = (mood == .celebrating || mood == .dancing) ? 0.15 : ((mood == .breakReminder || isWaiting) ? 0.13 : 0.08)
        let haloRect = CGRect(
            x: center.x - radius * 1.16,
            y: center.y - radius * 0.98,
            width: radius * 2.32,
            height: radius * 2.32
        )
        context.fill(Path(ellipseIn: haloRect), with: .color((isWaiting ? AgentIndicator.waitingColor : palette.accent).opacity(opacity)))
    }

    private static func drawCelebration(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        palette: PetPalette,
        animated: Bool
    ) {
        let alpha = PetShapes.celebrationAlpha(time: time, reducedMotion: !animated)
        guard alpha > 0.01 else { return }
        let fade = alpha / 0.9
        PetShapes.celebrationBase(
            in: &context,
            center: center,
            radius: radius,
            time: time,
            palette: palette,
            fade: fade,
            reducedMotion: !animated
        )

        let twinkle = animated ? CGFloat(0.72 + (sin(time * 7) + 1) * 0.14) : 0.86
        switch palette.animation.celebrationEffect {
        case .leaves:
            let leaves: [(CGFloat, CGFloat, CGFloat, Double)] = [
                (-0.72, -0.30, 0.20, 0.0), (0.70, -0.34, 0.20, 1.1),
                (-0.80, 0.22, 0.18, 2.2), (0.82, 0.20, 0.18, 3.3),
                (-0.36, -0.78, 0.16, 4.4), (0.38, -0.80, 0.16, 5.3)
            ]
            for (x, y, scale, phase) in leaves {
                let drift: CGFloat = animated ? CGFloat(sin(time * 4 + phase)) * radius * 0.035 : 0
                let from = CGPoint(x: center.x + x * radius, y: center.y + y * radius + drift)
                let to = CGPoint(x: from.x - radius * 0.14, y: from.y - radius * 0.26)
                let shimmer: CGFloat = animated ? 0.82 + 0.18 * CGFloat(0.5 + 0.5 * sin(time * 7 + phase)) : 1.0
                PetShapes.leaf(
                    in: &context,
                    from: from,
                    to: to,
                    radius: radius * scale * twinkle,
                    color: palette.accent.opacity(min(0.92 * shimmer * fade, 1.0))
                )
            }
        case .moonDust:
            let moonCenter = CGPoint(x: center.x + radius * 0.92, y: center.y - radius * 0.40)
            context.fill(
                PetShapes.crescent(center: moonCenter, radius: radius * 0.24),
                with: .color(palette.accent.opacity(min(0.92 * fade, 1.0)))
            )
            for index in 0..<12 {
                let phase = Double(index) * 0.9
                let angle = Double(index) * .pi * 2 / 12 + 0.3
                let distance: CGFloat = animated ? radius * (0.36 + 0.08 * CGFloat(sin(time * 2.5 + phase))) : radius * 0.36
                let point = CGPoint(
                    x: moonCenter.x + CGFloat(cos(angle)) * distance,
                    y: moonCenter.y + CGFloat(sin(angle)) * distance
                )
                let flicker: CGFloat = animated ? 0.55 + 0.45 * CGFloat(0.5 + 0.5 * sin(time * 6.0 + phase * 1.7)) : 1.0
                context.fill(
                    PetShapes.star(center: point, outerRadius: radius * 0.06 * flicker, innerRadius: radius * 0.018 * flicker),
                    with: .color(palette.furLight.opacity(min(0.95 * flicker * fade, 1.0)))
                )
            }
        case .berryHearts:
            let hearts: [(CGFloat, CGFloat, CGFloat, Double)] = [
                (-0.72, -0.36, 0.14, 0.0), (0.74, -0.46, 0.17, 2.1), (-0.66, 0.20, 0.11, 4.2)
            ]
            for (x, y, scale, phase) in hearts {
                let point = CGPoint(x: center.x + x * radius, y: center.y + y * radius)
                let beat: CGFloat = animated ? 1.0 + 0.10 * CGFloat(sin(time * 6.0 + phase)) : 1.0
                context.fill(
                    PetShapes.heart(center: point, size: radius * scale * twinkle * beat),
                    with: .color(palette.cheek.opacity(min(0.92 * fade, 1.0)))
                )
            }
        case .starburst:
            let stars: [(CGFloat, CGFloat, CGFloat)] = [(-0.76, -0.42, 0.12), (0.74, -0.46, 0.15), (-0.70, 0.22, 0.09), (0.66, 0.24, 0.10)]
            for (x, y, scale) in stars {
                let point = CGPoint(x: center.x + x * radius, y: center.y + y * radius)
                context.fill(
                    PetShapes.star(center: point, outerRadius: radius * scale * twinkle, innerRadius: radius * scale * 0.32),
                    with: .color(palette.accent.opacity(min(0.95 * fade, 1.0)))
                )
            }
        }
    }
}
