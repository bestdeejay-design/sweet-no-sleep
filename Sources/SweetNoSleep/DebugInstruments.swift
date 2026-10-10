import AppKit
import Foundation

/// Debug-only instruments, gated behind the same opt-in as the agent bridge
/// (`agentBridge.enabled`) and documented in `docs/CODE_AUDIT.md`. They exist so
/// a script can show a mood on demand, place the panel exactly and set the pet
/// size, which is what makes "same mood, same spot" comparisons between two
/// builds possible. The user-facing READMEs never mention them.
///
/// URL forms (`sweetnosleep://`):
///
///     sweetnosleep://debug/mood?mood=<id>&duration=<seconds>
///     sweetnosleep://debug/mood?list=1
///     sweetnosleep://debug/place?x=<points>&y=<points>[&screen=<index>]
///     sweetnosleep://debug/size?pt=<45..170>
///
/// `--debug-moods` is the headless form of `?list=1`: it prints the ids and
/// exits, like the other `--…` reports in `main.swift`.
enum DebugInstruments {
    /// Every mood id `debug/mood` accepts, in declaration order.
    static let moodIDs = [
        "idle", "working", "celebrating", "dancing", "stretching", "curious",
        "breakReminder", "resting", "dragging", "walking", "waitingForApproval"
    ]

    static let defaultMoodDuration: TimeInterval = 6
    static let moodDurationRange: ClosedRange<TimeInterval> = 1...120
    static let petSizeRange: ClosedRange<Double> = 45...170

    /// The flag `main.swift` answers before the app starts: `SweetNoSleep --debug-moods`.
    static let moodsFlag = "--debug-moods"

    /// Prints the mood ids when `moodsFlag` is present.
    ///
    /// - Returns: The process exit status, or `nil` when the app should launch normally.
    static func runIfRequested() -> Int32? {
        guard CommandLine.arguments.contains(moodsFlag) else { return nil }
        for id in moodIDs {
            print(id)
        }
        return 0
    }

    /// One parsed debug request.
    enum Command: Equatable {
        case listMoods
        case mood(KiwiMood, duration: TimeInterval)
        case place(x: CGFloat, y: CGFloat, screen: Int?)
        case size(points: Double)
    }

    static func mood(for id: String) -> KiwiMood? {
        switch id.lowercased() {
        case "idle": return .idle
        case "working": return .working
        case "celebrating": return .celebrating
        case "dancing": return .dancing
        case "stretching": return .stretching
        case "curious": return .curious
        case "breakreminder": return .breakReminder
        case "resting": return .resting
        case "dragging": return .dragging
        case "walking": return .walking
        case "waitingforapproval": return .waitingForApproval
        default: return nil
        }
    }

    /// Parses `sweetnosleep://debug/...`; `nil` for any other URL, an unknown
    /// path, or a malformed value, so a stray link changes nothing.
    static func command(for url: URL) -> Command? {
        guard url.scheme?.lowercased() == "sweetnosleep",
              url.host?.lowercased() == "debug",
              let path = url.pathComponents.dropFirst().first?.lowercased()
        else { return nil }

        func value(_ name: String) -> String? {
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == name })?
                .value
        }

        switch path {
        case "mood":
            if value("list") != nil { return .listMoods }
            guard let id = value("mood"), let mood = mood(for: id) else { return nil }
            let seconds = value("duration").flatMap(Double.init) ?? defaultMoodDuration
            return .mood(mood, duration: min(max(seconds, moodDurationRange.lowerBound), moodDurationRange.upperBound))
        case "place":
            guard let x = value("x").flatMap(Double.init),
                  let y = value("y").flatMap(Double.init)
            else { return nil }
            let screen = value("screen").flatMap(Int.init)
            return .place(x: CGFloat(x), y: CGFloat(y), screen: screen)
        case "size":
            guard let points = value("pt").flatMap(Double.init) else { return nil }
            return .size(points: min(max(points, petSizeRange.lowerBound), petSizeRange.upperBound))
        default:
            return nil
        }
    }
}

/// Screen coordinates as a window list reports them: points with the origin at
/// the top-left of the primary display, x to the right, y down. AppKit's global
/// space has the same origin at the bottom-left, so `debug/place` translates.
///
/// Main-actor bound because `NSScreen` is; every caller is.
@MainActor
enum DebugScreenSpace {
    /// Height of the primary display, i.e. the top of AppKit's global space.
    static var primaryHeight: CGFloat {
        (NSScreen.screens.first ?? NSScreen.main)?.frame.maxY ?? 0
    }

    /// Flipped (top-left origin) y -> AppKit global y.
    static func appKitY(flippedY: CGFloat) -> CGFloat {
        primaryHeight - flippedY
    }

    /// A rect in flipped coordinates, from an AppKit rect.
    static func flipped(_ rect: NSRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
