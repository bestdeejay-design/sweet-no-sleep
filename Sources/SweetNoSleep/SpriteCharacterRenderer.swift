import SwiftUI

/// Draws sprite characters (`pet.json` packs) on the same Canvas as the
/// procedural cat: the body breathes, the tail wags around its pivot, and the
/// agent-awareness details (badge light, session count, waiting glyph) come from
/// the shared `AgentIndicator`, so behavior matches Kiwi exactly.
///
/// Format 2 packs add a layered rig: the head bobs, tilts and shakes around its
/// neck pivot, the three leg layers swing a phase-offset walk cycle around their
/// hip pivots, and vector eyes drawn at the rig's socket anchors track the
/// cursor, blink on Kiwi's cadence and close while resting - the same motion
/// vocabulary as `KiwiPetView`, applied to the watermelon cat's own artwork.
enum SpriteCharacterRenderer {
    /// Fraction of the canvas height the sprite occupies; keeps every character
    /// at the same on-screen size as the procedural cat.
    private static let spriteHeightRatio: CGFloat = 0.88
    /// Baseline the paws rest on, matching `KiwiPetView.drawPet`.
    private static let feetRatio: CGFloat = 0.862

    /// How the vector eyes of a rigged sprite character are drawn.
    private enum SpriteEyeState {
        case open
        case wide
        case half
        case closed
        case happy
    }

    /// One frame of rig motion: angles in radians, lifts as a fraction of the
    /// sprite side. Static offsets survive Reduce Motion; oscillations do not.
    private struct SpritePose {
        var headAngle: CGFloat = 0
        var headLift: CGFloat = 0
        var legAngleA: CGFloat = 0
        var legAngleB: CGFloat = 0
        var legAngleC: CGFloat = 0
        var eyes: SpriteEyeState = .open
    }

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
        gaze: CGPoint,
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

        let pose = rigPose(mood: mood, time: time, animated: animated)
        let rig = sprite.rig

        // Legs swing from the hip pivots before everything else, so the body's
        // static hip band covers the top of each rotated layer.
        if let rig, let legsA = sprite.legsA, let legsB = sprite.legsB, let legsC = sprite.legsC {
            let legs: [(CGImage, CGPoint, CGFloat)] = [
                (legsA, CGPoint(x: rect.minX + rig.legPivotAX * rect.width, y: rect.minY + rig.legPivotAY * rect.height), pose.legAngleA),
                (legsB, CGPoint(x: rect.minX + rig.legPivotBX * rect.width, y: rect.minY + rig.legPivotBY * rect.height), pose.legAngleB),
                (legsC, CGPoint(x: rect.minX + rig.legPivotCX * rect.width, y: rect.minY + rig.legPivotCY * rect.height), pose.legAngleC)
            ]
            for (image, pivot, angle) in legs {
                drawLayered(in: &context, image: image, rect: rect, pivot: pivot, angle: angle)
            }
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

        // The head carries the vector eyes, so both share one transform and the
        // gaze stays glued to the face while it bobs and tilts.
        if let rig, let head = sprite.head {
            let headPivot = CGPoint(
                x: rect.minX + rig.headPivotX * rect.width,
                y: rect.minY + rig.headPivotY * rect.height
            )
            context.drawLayer { headLayer in
                headLayer.translateBy(x: 0, y: pose.headLift * side)
                headLayer.concatenate(CGAffineTransform(translationX: headPivot.x, y: headPivot.y))
                headLayer.concatenate(CGAffineTransform(rotationAngle: pose.headAngle))
                headLayer.concatenate(CGAffineTransform(translationX: -headPivot.x, y: -headPivot.y))
                headLayer.draw(Image(decorative: head, scale: 1), in: rect)
                drawEyes(in: &headLayer, rect: rect, rig: rig, palette: palette, gaze: gaze, state: pose.eyes)
            }
        }

        // Reduce Motion / animations off: a static pose with no particles. The
        // non-motion awareness cues (halo, badge light, waiting glyph) stay.
        if animated {
            if isCelebrating {
                drawPettingHearts(in: &context, rect: rect, time: time, palette: palette, animated: animated)
            }
            if isCelebrating || isDancing {
                drawCelebration(in: &context, center: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.5), radius: side * 0.44, time: time, palette: palette, animated: animated)
            }
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

    // MARK: Rig motion

    /// The mood-to-motion mapping of the layered rig. Every `KiwiMood` reads
    /// differently: the table is documented in `docs/SKIN_AUTHORING.md`.
    private static func rigPose(mood: KiwiMood, time: Double, animated: Bool) -> SpritePose {
        var pose = SpritePose()
        let degrees = CGFloat.pi / 180
        // Gentle head tilt roughly every 18 s during calm moods, mirroring
        // `KiwiPetView.headTiltAngle` at a smaller amplitude: the sprite head is
        // a raster layer, so its cut tolerates less rotation than Kiwi's vectors.
        func calmTilt(amplitude: CGFloat) -> CGFloat {
            guard animated else { return 0 }
            let period = 18.0
            let phase = time.truncatingRemainder(dividingBy: period)
            guard phase >= 0, phase < 2.0 else { return 0 }
            let t = phase / 2.0
            let envelope = smoothstep(0, 0.4, t) * (1 - smoothstep(0.6, 1.0, t))
            let direction: CGFloat = Int(floor(time / period)).isMultiple(of: 2) ? 1 : -1
            return direction * amplitude * CGFloat(envelope)
        }

        switch mood {
        case .idle:
            pose.headLift = animated ? CGFloat(sin(time * 1.45)) * 0.006 : 0
            pose.headAngle = calmTilt(amplitude: 2.0 * degrees)
        case .working:
            pose.headLift = animated ? CGFloat(sin(time * 1.9)) * 0.005 : 0
            pose.headAngle = calmTilt(amplitude: 1.4 * degrees)
        case .celebrating:
            pose.headAngle = animated ? CGFloat(sin(time * 6.2)) * 2.4 * degrees : 0
            pose.headLift = animated ? -CGFloat(abs(sin(time * 3.1))) * 0.010 : -0.006
            pose.legAngleA = animated ? CGFloat(sin(time * 6.2)) * 4 * degrees : 0
            pose.legAngleC = pose.legAngleA
            pose.legAngleB = -pose.legAngleA
            pose.eyes = .happy
        case .dancing:
            pose.headAngle = animated ? CGFloat(sin(time * 6.2)) * 3 * degrees : 0
            pose.headLift = animated ? -CGFloat(abs(sin(time * 6.2))) * 0.012 : 0
            pose.legAngleA = animated ? CGFloat(sin(time * 6.2)) * 5 * degrees : 0
            pose.legAngleC = pose.legAngleA
            pose.legAngleB = -pose.legAngleA
            pose.eyes = .happy
        case .stretching:
            pose.headAngle = -2.0 * degrees
            pose.headLift = -0.008
            pose.legAngleA = 6.0 * degrees
            pose.legAngleC = -6.0 * degrees
            pose.eyes = .half
        case .curious:
            pose.headAngle = 3.0 * degrees + (animated ? CGFloat(sin(time * 2.2)) * 0.6 * degrees : 0)
            pose.eyes = .wide
        case .breakReminder:
            pose.headAngle = -2.0 * degrees
            pose.headLift = 0.004
            pose.eyes = .half
        case .resting:
            pose.headAngle = 1.5 * degrees
            pose.headLift = 0.010
            pose.legAngleA = -3.0 * degrees
            pose.legAngleC = -3.0 * degrees
            pose.legAngleB = 3.0 * degrees
            pose.eyes = .closed
        case .dragging:
            pose.headAngle = animated ? CGFloat(sin(time * 9)) * 1.5 * degrees : 0
            pose.legAngleA = animated ? CGFloat(sin(time * 9)) * 7 * degrees : 0
            pose.legAngleC = animated ? -CGFloat(sin(time * 9)) * 7 * degrees : 0
            pose.legAngleB = animated ? CGFloat(sin(time * 9 + 1.0)) * 5 * degrees : 0
            pose.eyes = .wide
        case .walking:
            pose.headLift = animated ? CGFloat(abs(sin(time * 8))) * 0.004 : 0
            pose.legAngleA = animated ? CGFloat(sin(time * 8)) * 6 * degrees : 0
            pose.legAngleC = pose.legAngleA
            pose.legAngleB = -pose.legAngleA
        case .waitingForApproval:
            pose.headAngle = 1.5 * degrees
            pose.headLift = -0.010
            pose.eyes = .wide
        }

        // Kiwi's blink cadence, so both cats blink in the same rhythm.
        if animated, pose.eyes == .open || pose.eyes == .wide {
            let blinkCycle = time.truncatingRemainder(dividingBy: 4.6)
            if blinkCycle >= 0, blinkCycle < 0.14 {
                pose.eyes = .closed
            }
        }
        return pose
    }

    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let clamped = min(max((x - a) / (b - a), 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    // MARK: Layers and eyes

    private static func drawLayered(
        in context: inout GraphicsContext,
        image: CGImage,
        rect: CGRect,
        pivot: CGPoint,
        angle: CGFloat
    ) {
        guard angle != 0 else {
            context.draw(Image(decorative: image, scale: 1), in: rect)
            return
        }
        context.drawLayer { layer in
            layer.concatenate(CGAffineTransform(translationX: pivot.x, y: pivot.y))
            layer.concatenate(CGAffineTransform(rotationAngle: angle))
            layer.concatenate(CGAffineTransform(translationX: -pivot.x, y: -pivot.y))
            layer.draw(Image(decorative: image, scale: 1), in: rect)
        }
    }

    /// Vector eyes at the rig's socket anchors: they track the cursor, blink,
    /// squint and close, and stay readable at the 45 pt minimum pet size.
    private static func drawEyes(
        in context: inout GraphicsContext,
        rect: CGRect,
        rig: PetCharacterRig,
        palette: PetPalette,
        gaze: CGPoint,
        state: SpriteEyeState
    ) {
        let sockets: [(x: Double, y: Double)] = [
            (rig.eyeLeftX, rig.eyeLeftY),
            (rig.eyeRightX, rig.eyeRightY)
        ]
        for socket in sockets {
            let center = CGPoint(
                x: rect.minX + CGFloat(socket.x) * rect.width,
                y: rect.minY + CGFloat(socket.y) * rect.height
            )
            let radiusX = CGFloat(rig.eyeRadiusX) * rect.width
            let radiusY = CGFloat(rig.eyeRadiusY) * rect.height
            // gaze.y is positive when the cursor sits below the pet, matching
            // `KiwiPetView.cursorGaze`, so it maps straight to screen space.
            let gazeX = CGFloat(gaze.x) * radiusX * 0.42
            let gazeY = CGFloat(gaze.y) * radiusY * 0.38

            switch state {
            case .closed, .happy:
                let arc = closedEyePath(center: center, radiusX: radiusX, radiusY: radiusY, happy: state == .happy)
                context.stroke(
                    arc,
                    with: .color(palette.outline),
                    style: StrokeStyle(lineWidth: max(radiusX * 0.62, 1.2), lineCap: .round)
                )
            case .half:
                let lid = CGRect(
                    x: center.x - radiusX + gazeX,
                    y: center.y - radiusY * 0.28 + gazeY,
                    width: radiusX * 2,
                    height: radiusY * 1.1
                )
                context.fill(Path(ellipseIn: lid), with: .color(palette.outline))
                var line = Path()
                line.move(to: CGPoint(x: center.x - radiusX * 1.12 + gazeX, y: center.y - radiusY * 0.28 + gazeY))
                line.addLine(to: CGPoint(x: center.x + radiusX * 1.12 + gazeX, y: center.y - radiusY * 0.28 + gazeY))
                context.stroke(line, with: .color(palette.outline), style: StrokeStyle(lineWidth: max(radiusX * 0.42, 1), lineCap: .round))
            case .open, .wide:
                let scale: CGFloat = state == .wide ? 1.18 : 1.0
                let eye = CGRect(
                    x: center.x - radiusX * scale + gazeX,
                    y: center.y - radiusY * scale + gazeY,
                    width: radiusX * 2 * scale,
                    height: radiusY * 2 * scale
                )
                context.fill(Path(ellipseIn: eye), with: .color(palette.outline))
                let shine = radiusX * 0.30 * scale
                let shineRect = CGRect(
                    x: center.x - radiusX * 0.34 * scale + gazeX * 0.8 - shine / 2,
                    y: center.y - radiusY * 0.42 * scale + gazeY * 0.8 - shine / 2,
                    width: shine,
                    height: shine
                )
                context.fill(Path(ellipseIn: shineRect), with: .color(.white.opacity(0.92)))
            }
        }
    }

    private static func closedEyePath(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, happy: Bool) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x - radiusX, y: center.y))
        path.addQuadCurve(
            to: CGPoint(x: center.x + radiusX, y: center.y),
            control: CGPoint(x: center.x, y: center.y + radiusY * (happy ? 1.15 : 0.68))
        )
        return path
    }

    /// Cheek-heart burst when the pet is petted (`model.poke()` sets the
    /// celebrating mood): the Kiwi cheek heart plus two phased companions.
    private static func drawPettingHearts(
        in context: inout GraphicsContext,
        rect: CGRect,
        time: Double,
        palette: PetPalette,
        animated: Bool
    ) {
        let hearts: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (0.34, 0.30, 0.115, 0.0),
            (0.46, 0.16, 0.075, 1.3),
            (0.24, 0.14, 0.058, 2.4)
        ]
        for (x, y, scale, phase) in hearts {
            let beat: CGFloat = animated ? 1.0 + 0.10 * CGFloat(sin(time * 6.0 + phase)) : 1.0
            let center = CGPoint(x: rect.minX + rect.width * (0.5 + x), y: rect.minY + rect.height * (0.5 + y))
            context.fill(
                PetShapes.heart(center: center, size: rect.width * scale * beat),
                with: .color(palette.cheek.opacity(0.85))
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
