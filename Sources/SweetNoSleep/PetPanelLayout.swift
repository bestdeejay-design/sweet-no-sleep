import Foundation

/// One source of truth for the pet panel's content geometry.
///
/// The bubble/pet stack is laid out by SwiftUI (`PetDesktopView`) while the
/// panel frame is owned by AppKit (`PetPanelController`). When the two sides
/// computed their sizes from different predicates - the view from
/// `hasWaitingAgent`, the controller from the dismissal-aware session list -
/// dismissing the waiting bubble shrank the panel around a bubble the view
/// still showed, clipping the pet (issue #21 P0). Both sides now call into this
/// type, and the view passes the same dismissal-aware flag the controller uses,
/// so a dismissed cue occupies no space anywhere.
///
/// The pet itself is laid out in a **pet frame** of `petSize + 48` points - the
/// square v1 filled end to end, so the pet's on-screen size at a given
/// `petSize` never changes - and the panel holds a larger **canvas** around it.
/// The extra ring is the room the mood effects need since the B-25 follow-up
/// restored the pre-fix effect radii instead of shrinking them (issue #30); it
/// is also why the panel is wider than `petSize + 48` and why the pets are
/// placed relative to the canvas' top-left, the corner a drag persists.
enum PetPanelLayout {
    static let waitingBubbleWidth: CGFloat = 228
    static let waitingBubbleHeight: CGFloat = 100
    static let breakBubbleWidth: CGFloat = 228
    /// 96 pt clears the layered-rig head at the 45 pt pet size (the old 88 pt
    /// formula predates the head layer).
    static let breakBubbleHeight: CGFloat = 96
    /// Transparent margin the pet frame keeps around the sprite.
    static let petCanvasMargin: CGFloat = 48
    /// How much larger than the pet frame the canvas is.
    ///
    /// Arithmetic behind 1.25, with the sprite side `side = 0.88 * frame`:
    ///
    /// * the sprite halo is a circle of radius `1.16 * 0.52 = 0.6032 side`
    ///   centered `0.18 * 0.52 = 0.0936 side` below the sprite's 56 % line, so
    ///   its lowest pixel is `-0.0205 + 0.56 + 0.0936 + 0.6032 = 1.236 side` -
    ///   `1.088 frame` sides - below the frame's top: the binding constraint;
    /// * the same halo is `1.2064 side = 1.062 frame` sides wide, and the
    ///   `kot-arbuz-moonlight` moon-dust stars reach `1.042 frame` sides right
    ///   of the frame's left edge;
    /// * `1.25` covers the worst of them with ~13 % of a frame side of room for
    ///   the anti-aliased edge, and it is what the committed render loop uses
    ///   (`Scripts/render-character-animations.py`, `CANVAS_SCALE`).
    static let auraCanvasScale: CGFloat = 1.25

    /// The square the pet is laid out in, at the drawn size it has always had.
    static func petFrame(petSize: CGFloat) -> CGFloat {
        petSize + petCanvasMargin
    }

    /// The square the view and the window hold: the pet frame plus the margin
    /// its mood effects need.
    static func petCanvas(petSize: CGFloat) -> CGFloat {
        petFrame(petSize: petSize) * auraCanvasScale
    }

    /// Distance from the canvas' top-left corner to the pet frame's top-left.
    /// The frame is centered, so this is the margin on every side.
    static func petFrameOrigin(petSize: CGFloat) -> CGFloat {
        (petCanvas(petSize: petSize) - petFrame(petSize: petSize)) / 2
    }

    /// Height the bubble currently on screen adds above the pet.
    static func bubbleHeight(showsWaitingBubble: Bool, isBreakDue: Bool) -> CGFloat {
        // Waiting for an agent decision takes precedence over the break reminder.
        if showsWaitingBubble { return waitingBubbleHeight }
        if isBreakDue { return breakBubbleHeight }
        return 0
    }

    static func contentWidth(petSize: CGFloat, showsWaitingBubble: Bool, isBreakDue: Bool) -> CGFloat {
        let side = petCanvas(petSize: petSize)
        if showsWaitingBubble { return max(side, waitingBubbleWidth) }
        if isBreakDue { return max(side, breakBubbleWidth) }
        return side
    }

    /// The laid-out size of the pet content: the panel frame and the SwiftUI
    /// stack must both use exactly this.
    static func contentSize(petSize: CGFloat, showsWaitingBubble: Bool, isBreakDue: Bool) -> NSSize {
        NSSize(
            width: contentWidth(petSize: petSize, showsWaitingBubble: showsWaitingBubble, isBreakDue: isBreakDue),
            height: petCanvas(petSize: petSize) + bubbleHeight(showsWaitingBubble: showsWaitingBubble, isBreakDue: isBreakDue)
        )
    }

    /// Space the visible bubble occupies above the pet, used to aim the
    /// cursor gaze at the sprite rather than at the panel centre.
    static func topInset(showsWaitingBubble: Bool, isBreakDue: Bool) -> CGFloat {
        bubbleHeight(showsWaitingBubble: showsWaitingBubble, isBreakDue: isBreakDue)
    }
}
