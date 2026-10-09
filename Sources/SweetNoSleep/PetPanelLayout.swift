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
enum PetPanelLayout {
    static let waitingBubbleWidth: CGFloat = 228
    static let waitingBubbleHeight: CGFloat = 100
    static let breakBubbleWidth: CGFloat = 228
    /// 96 pt clears the layered-rig head at the 45 pt pet size (the old 88 pt
    /// formula predates the head layer).
    static let breakBubbleHeight: CGFloat = 96
    /// Transparent margin the pet canvas keeps around the sprite.
    static let petCanvasMargin: CGFloat = 48

    static func petSide(petSize: CGFloat) -> CGFloat {
        petSize + petCanvasMargin
    }

    /// Height the bubble currently on screen adds above the pet.
    static func bubbleHeight(showsWaitingBubble: Bool, isBreakDue: Bool) -> CGFloat {
        // Waiting for an agent decision takes precedence over the break reminder.
        if showsWaitingBubble { return waitingBubbleHeight }
        if isBreakDue { return breakBubbleHeight }
        return 0
    }

    static func contentWidth(petSize: CGFloat, showsWaitingBubble: Bool, isBreakDue: Bool) -> CGFloat {
        let side = petSide(petSize: petSize)
        if showsWaitingBubble { return max(side, waitingBubbleWidth) }
        if isBreakDue { return max(side, breakBubbleWidth) }
        return side
    }

    /// The laid-out size of the pet content: the panel frame and the SwiftUI
    /// stack must both use exactly this.
    static func contentSize(petSize: CGFloat, showsWaitingBubble: Bool, isBreakDue: Bool) -> NSSize {
        NSSize(
            width: contentWidth(petSize: petSize, showsWaitingBubble: showsWaitingBubble, isBreakDue: isBreakDue),
            height: petSide(petSize: petSize) + bubbleHeight(showsWaitingBubble: showsWaitingBubble, isBreakDue: isBreakDue)
        )
    }

    /// Space the visible bubble occupies above the pet, used to aim the
    /// cursor gaze at the sprite rather than at the panel centre.
    static func topInset(showsWaitingBubble: Bool, isBreakDue: Bool) -> CGFloat {
        bubbleHeight(showsWaitingBubble: showsWaitingBubble, isBreakDue: isBreakDue)
    }
}
