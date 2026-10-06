import CoreGraphics
import Combine
import Dispatch

// State container for Kiwi, the SweetNoSleep desktop pet.
// Owned by this file; PowerKeeper itself is owned by a sibling agent
// and is only referenced by name here (see attach(_:)).
final class KiwiBrain: ObservableObject {

    // Visual/behavioral state of the pet.
    enum PetState: Equatable {
        case idle
        case dragged
        case reacting
        case sleeping
    }

    // Current pet state, drives the pet view animation.
    @Published var state: PetState = .idle

    // Last known pet position in screen coordinates.
    // The panel owner updates this when the pet is moved.
    @Published var position: CGPoint = .zero

    // When true the Mac is kept awake via PowerKeeper.
    // The sibling-owned PowerKeeper exposes keepAwake(reason:) / letSleep();
    // the app forwards isAwake changes through awakeHandler (see attachAwakeHandler).
    @Published var isAwake: Bool = false {
        didSet {
            guard isAwake != oldValue else { return }
            awakeHandler?(isAwake)
        }
    }

    // Closure the app wires to PowerKeeper, e.g.:
    //   brain.awakeHandler = { [weak keeper] in keeper?.setAwake($0) }
    // Using a closure keeps this file compilable before PowerKeeper lands.
    var awakeHandler: ((Bool) -> Void)?

    // Pending auto-return from reacting to idle; reset on every poke.
    private var pokeWork: DispatchWorkItem?

    // Happy reaction visible duration in seconds.
    private static let reactDuration: Double = 0.9

    init(
        state: PetState = .idle,
        position: CGPoint = .zero,
        isAwake: Bool = false
    ) {
        self.state = state
        self.position = position
        self.isAwake = isAwake
    }

    // Convenience for the app scene to forward awake changes to PowerKeeper
    // without this file importing the concrete type.
    func attachAwakeHandler(_ handler: @escaping (Bool) -> Void) {
        self.awakeHandler = handler
    }

    // Tap on the pet: happy squash + heart pop, then back to idle.
    func poke() {
        pokeWork?.cancel()
        state = .reacting
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.state == .reacting {
                self.state = .idle
            }
        }
        pokeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reactDuration, execute: work)
    }

    // Drag start: stretch state, dropping any pending poke timer.
    func beginDrag() {
        pokeWork?.cancel()
        pokeWork = nil
        state = .dragged
    }

    // Drag end: settle back to idle.
    func endDrag() {
        state = .idle
    }
}
