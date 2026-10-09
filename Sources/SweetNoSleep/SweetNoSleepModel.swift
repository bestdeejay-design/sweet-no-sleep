import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Companion and session models

enum KiwiMood: Equatable, Sendable {
    case idle
    case working
    case celebrating
    case dancing
    case stretching
    case curious
    case breakReminder
    case resting
    case dragging
    case walking
    /// An agent session asked for input; the pet holds an attentive pose.
    case waitingForApproval
}

/// One local agent session held open by the URL-scheme bridge.
enum AgentSessionStatus: String, Equatable, Sendable {
    case working
    case waiting
}

struct AgentSessionState: Equatable, Sendable {
    var status: AgentSessionStatus
    var startedAt: Date
    var lastActivityAt: Date
    var expiry: Date
    var reason: String?

    var isWaiting: Bool { status == .waiting }
}

/// Read-only view of a session for the menu bar dashboard.
struct AgentSessionSummary: Identifiable, Equatable {
    let id: String
    let status: AgentSessionStatus
    let startedAt: Date
    let reason: String?

    var isWaiting: Bool { status == .waiting }

    /// Short form shown in the dashboard rows.
    var shortID: String { String(id.prefix(10)) }
}

enum SessionCompletionAction: String, CaseIterable, Identifiable, Hashable {
    case allowNormalSleep
    case sleepImmediately

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allowNormalSleep: L10n.text("Allow normal sleep")
        case .sleepImmediately: L10n.text("Put the Mac to sleep immediately")
        }
    }

    func detail(persona: String) -> String {
        switch self {
        case .allowNormalSleep:
            L10n.text("Release the sleep assertion and let macOS use its normal energy settings.")
        case .sleepImmediately:
            L10n.format("After a confirmed session, %@ will request immediate system sleep.", persona)
        }
    }
}

/// Shared application state for the menu, settings, pet window and power keeper.
@MainActor
final class SweetNoSleepModel: ObservableObject {
    static let shared = SweetNoSleepModel()

    private let defaults = UserDefaults.standard
    private let powerKeeper = PowerKeeper()
    private let powerSourceMonitor = PowerSourceMonitor()
    private var sessionTimer: Timer?
    private var heartbeatTimer: Timer?
    private var moodTimer: Timer?
    private var playfulTimer: Timer?
    private var breakTimer: Timer?
    private var sessionEndDate: Date?
    private var sessionCompletionAction: SessionCompletionAction?
    private var pendingImmediateSleepToken: UUID?
    private var manualAwake = false
    private var agentLeaseTimer: Timer?
    private var agentWebhookServer: AgentWebhookServer?
    private var skinWatchTimer: Timer?
    private var lastSkinsSignature = ""
    // Last system wake time. Taps within the grace window are ignored so a
    // click meant to wake the Mac does not accidentally poke the pet.
    private var lastSystemWakeDate: Date?
    private var wakeObserver: NSObjectProtocol?
    private var holdStartUptime: TimeInterval?
    private var hasCapTripped = false
    private var isPausedByBatteryFloor = false
    private static let agentLeaseTimeout: TimeInterval = 180
    /// A session that asked for a human answer keeps its lease longer: the
    /// agent process is blocked on the answer and cannot heartbeat, so the
    /// working lease would drop the cue - and the sleep protection - while the
    /// question is still open (issue #21 audit).
    private static let waitingLeaseTimeout: TimeInterval = 600

    @Published private(set) var isKeepingAwake = false {
        didSet {
            if oldValue != isKeepingAwake { schedulePlayfulMoment() }
        }
    }
    @Published private(set) var isFocusSession = false
    /// Sessions the local agent bridge currently holds open.
    @Published private(set) var agentSessions: [String: AgentSessionState] = [:]
    /// Waiting sessions the user closed the bubble for (the cue itself stays).
    @Published private(set) var dismissedWaitingIDs: Set<String> = []
    /// Number of sessions the local agent bridge currently holds open.
    var activeAgentCount: Int { agentSessions.count }
    /// True while at least one session waits for a human answer.
    var hasWaitingAgent: Bool { agentSessions.values.contains { $0.isWaiting } }
    /// Waiting sessions the user has not closed the bubble for yet.
    var showsWaitingBubble: Bool {
        agentSessions.contains { session in
            session.value.isWaiting && !dismissedWaitingIDs.contains(session.key)
        }
    }
    /// Reason reported with the waiting event, if any.
    var agentWaitingReason: String? {
        agentSessions
            .filter { $0.value.isWaiting }
            .sorted { $0.key < $1.key }
            .compactMap(\.value.reason)
            .first
    }
    /// What the pet's chest light shows right now.
    var agentLightState: AgentLightState {
        guard agentIndicatorEnabled, !agentSessions.isEmpty else { return .off }
        return hasWaitingAgent ? .waiting : .working
    }
    /// Dashboard rows: waiting sessions first, then the oldest session.
    var agentSessionSummaries: [AgentSessionSummary] {
        agentSessions
            .map { AgentSessionSummary(id: $0.key, status: $0.value.status, startedAt: $0.value.startedAt, reason: $0.value.reason) }
            .sorted { lhs, rhs in
                if lhs.isWaiting != rhs.isWaiting { return lhs.isWaiting }
                return lhs.startedAt < rhs.startedAt
            }
    }
    @Published private(set) var remainingSeconds: Int?
    @Published private(set) var powerWarning: String?
    @Published var statusMessage = ""
    @Published private(set) var mood: KiwiMood = .idle
    @Published private(set) var diagnostics = PowerDiagnostics()

    @Published var selectedMinutes: Int {
        didSet { defaults.set(selectedMinutes, forKey: Key.selectedMinutes) }
    }

    @Published private(set) var availableSkins: [PetSkinDefinition] = []

    @Published var selectedSkinID: String {
        didSet { defaults.set(selectedSkinID, forKey: Key.skin) }
    }

    var activeSkin: PetSkinDefinition {
        availableSkins.first(where: { $0.id == selectedSkinID }) ?? availableSkins.first ?? .fallback
    }

    /// The persona the active skin plays in the UI: "Kiwi" for the built-in
    /// cat's skins, the pack's own `characterName` for character packs such as
    /// Kot-Arbuz, so the app never calls a different cat "Kiwi".
    var characterName: String { activeSkin.personaName }

    @Published var petSize: Double {
        didSet { defaults.set(petSize, forKey: Key.petSize) }
    }

    @Published var keepDisplayAwake: Bool {
        didSet {
            defaults.set(keepDisplayAwake, forKey: Key.keepDisplayAwake)
            guard oldValue != keepDisplayAwake, isKeepingAwake else { return }
            refreshPowerAssertions()
        }
    }

    @Published var batteryFloorPercent: Int {
        didSet {
            defaults.set(batteryFloorPercent, forKey: Key.batteryFloorPercent)
            handlePowerSourceChange(powerSourceMonitor.currentStatus)
        }
    }

    @Published var continuousAwakeCapHours: Int {
        didSet {
            defaults.set(continuousAwakeCapHours, forKey: Key.continuousAwakeCapHours)
            checkAwakeCap()
        }
    }

    @Published var completionAction: SessionCompletionAction {
        didSet { defaults.set(completionAction.rawValue, forKey: Key.completionAction) }
    }

    @Published var resumeKeepAwakeOnLaunch: Bool {
        didSet { defaults.set(resumeKeepAwakeOnLaunch, forKey: Key.resumeOnLaunch) }
    }

    @Published var agentBridgeEnabled: Bool {
        didSet {
            defaults.set(agentBridgeEnabled, forKey: Key.agentBridgeEnabled)
            if oldValue && !agentBridgeEnabled { endAgentSessions() }
        }
    }

    @Published private(set) var agentWebhookError: String?

    @Published var agentWebhookEnabled: Bool {
        didSet {
            defaults.set(agentWebhookEnabled, forKey: Key.agentWebhookEnabled)
            if oldValue != agentWebhookEnabled {
                if agentWebhookEnabled { startWebhookServer() } else { stopWebhookServer() }
            }
        }
    }

    @Published var agentWebhookToken: String {
        didSet { defaults.set(agentWebhookToken, forKey: Key.agentWebhookToken) }
    }

    /// Chest badge light plus the active-session count on the pet.
    @Published var agentIndicatorEnabled: Bool {
        didSet { defaults.set(agentIndicatorEnabled, forKey: Key.agentIndicatorEnabled) }
    }

    @Published var isPetVisible: Bool {
        didSet {
            defaults.set(isPetVisible, forKey: Key.petVisible)
            if isPetVisible { schedulePlayfulMoment() } else { playfulTimer?.invalidate(); playfulTimer = nil }
        }
    }

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }

    @Published var roamingEnabled: Bool {
        didSet { defaults.set(roamingEnabled, forKey: Key.roamingEnabled) }
    }

    @Published var animationsEnabled: Bool {
        didSet {
            defaults.set(animationsEnabled, forKey: Key.animationsEnabled)
            schedulePlayfulMoment()
        }
    }

    @Published var playfulMomentsEnabled: Bool {
        didSet {
            defaults.set(playfulMomentsEnabled, forKey: Key.playfulMomentsEnabled)
            schedulePlayfulMoment()
        }
    }

    @Published var playfulMomentIntervalSeconds: Int {
        didSet {
            defaults.set(playfulMomentIntervalSeconds, forKey: Key.playfulMomentIntervalSeconds)
            schedulePlayfulMoment()
        }
    }

    @Published var playfulDancingWeight: Int {
        didSet {
            defaults.set(playfulDancingWeight, forKey: Key.playfulDancingWeight)
            schedulePlayfulMoment()
        }
    }

    @Published var playfulStretchingWeight: Int {
        didSet {
            defaults.set(playfulStretchingWeight, forKey: Key.playfulStretchingWeight)
            schedulePlayfulMoment()
        }
    }

    @Published var playfulCuriousWeight: Int {
        didSet {
            defaults.set(playfulCuriousWeight, forKey: Key.playfulCuriousWeight)
            schedulePlayfulMoment()
        }
    }

    @Published var breakRemindersEnabled: Bool {
        didSet {
            defaults.set(breakRemindersEnabled, forKey: Key.breakRemindersEnabled)
            if breakRemindersEnabled { scheduleBreakReminder() }
            else {
                breakTimer?.invalidate()
                breakTimer = nil
                if isBreakDue {
                    isBreakDue = false
                    setMood(baseMood())
                }
            }
            schedulePlayfulMoment()
        }
    }

    @Published var breakIntervalMinutes: Int {
        didSet {
            defaults.set(breakIntervalMinutes, forKey: Key.breakIntervalMinutes)
            if breakRemindersEnabled && isKeepingAwake && !isBreakDue { scheduleBreakReminder() }
        }
    }

    @Published private(set) var isBreakDue = false

    private init() {
        let defaults = UserDefaults.standard
        let loadedSkins = PetSkinLibrary.load()
        let usableSkins = loadedSkins.isEmpty ? [.fallback] : loadedSkins
        let savedSkinID = defaults.string(forKey: Key.skin)
        let savedAction = defaults.string(forKey: Key.completionAction)
            .flatMap(SessionCompletionAction.init(rawValue:)) ?? .allowNormalSleep
        let savedMinutes = defaults.object(forKey: Key.selectedMinutes) as? Int ?? 50
        let savedSize = defaults.object(forKey: Key.petSize) as? Double ?? 132

        availableSkins = usableSkins
        selectedSkinID = usableSkins.first(where: { $0.id == (savedSkinID ?? "") })?.id ?? usableSkins[0].id
        completionAction = savedAction
        selectedMinutes = min(max(savedMinutes, 15), 240)
        petSize = min(max(savedSize, 45), 170)
        keepDisplayAwake = defaults.object(forKey: Key.keepDisplayAwake) as? Bool ?? false
        batteryFloorPercent = min(max(defaults.object(forKey: Key.batteryFloorPercent) as? Int ?? 20, 0), 50)
        continuousAwakeCapHours = min(max(defaults.object(forKey: Key.continuousAwakeCapHours) as? Int ?? 4, 0), 12)
        resumeKeepAwakeOnLaunch = defaults.object(forKey: Key.resumeOnLaunch) as? Bool ?? false
        agentBridgeEnabled = defaults.object(forKey: Key.agentBridgeEnabled) as? Bool ?? false
        agentIndicatorEnabled = defaults.object(forKey: Key.agentIndicatorEnabled) as? Bool ?? true
        agentWebhookEnabled = defaults.object(forKey: Key.agentWebhookEnabled) as? Bool ?? false
        if let savedToken = defaults.string(forKey: Key.agentWebhookToken), Self.isValidWebhookToken(savedToken) {
            agentWebhookToken = savedToken
        } else {
            let freshToken = Self.makeWebhookToken()
            defaults.set(freshToken, forKey: Key.agentWebhookToken)
            agentWebhookToken = freshToken
        }
        isPetVisible = defaults.object(forKey: Key.petVisible) as? Bool ?? true
        alwaysOnTop = defaults.object(forKey: Key.alwaysOnTop) as? Bool ?? true
        roamingEnabled = defaults.object(forKey: Key.roamingEnabled) as? Bool ?? false
        animationsEnabled = defaults.object(forKey: Key.animationsEnabled) as? Bool ?? true
        playfulMomentsEnabled = defaults.object(forKey: Key.playfulMomentsEnabled) as? Bool ?? true
        playfulMomentIntervalSeconds = min(
            max(defaults.object(forKey: Key.playfulMomentIntervalSeconds) as? Int ?? 90, 15),
            120
        )
        playfulDancingWeight = min(
            max(defaults.object(forKey: Key.playfulDancingWeight) as? Int ?? 5, 0),
            10
        )
        playfulStretchingWeight = min(
            max(defaults.object(forKey: Key.playfulStretchingWeight) as? Int ?? 5, 0),
            10
        )
        playfulCuriousWeight = min(
            max(defaults.object(forKey: Key.playfulCuriousWeight) as? Int ?? 5, 0),
            10
        )
        breakRemindersEnabled = defaults.object(forKey: Key.breakRemindersEnabled) as? Bool ?? true
        breakIntervalMinutes = min(max(defaults.object(forKey: Key.breakIntervalMinutes) as? Int ?? 25, 10), 60)

        powerKeeper.onFailure = { [weak self] message in
            guard let self else { return }
            self.sessionTimer?.invalidate()
            self.sessionTimer = nil
            self.breakTimer?.invalidate()
            self.breakTimer = nil
            self.stopHeartbeatTimer()
            self.isBreakDue = false
            self.sessionEndDate = nil
            self.sessionCompletionAction = nil
            self.remainingSeconds = nil
            self.isFocusSession = false
            self.manualAwake = false
            self.isKeepingAwake = false
            self.holdStartUptime = nil
            self.powerWarning = message
            self.statusMessage = message
            self.setTemporaryMood(.resting, duration: 1.8, then: .idle)
            self.updateDiagnostics()
        }
        powerKeeper.onWarning = { [weak self] message in
            self?.powerWarning = message
            self?.statusMessage = message
            self?.updateDiagnostics()
        }

        // The greeting needs the loaded skin, so it cannot live in the
        // property initializer.
        statusMessage = L10n.format("%@ is ready to keep you company", characterName)

        if agentWebhookEnabled {
            startWebhookServer()
        }
        powerKeeper.onDiagnosticsChanged = { [weak self] in
            self?.updateDiagnostics()
        }
        powerSourceMonitor.onStatusChange = { [weak self] status in
            self?.handlePowerSourceChange(status)
        }
        // Track system wake to grant taps a short grace period afterwards.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastSystemWakeDate = Date()
                self?.updateDiagnostics()
            }
        }
        updateDiagnostics()
        schedulePlayfulMoment()
        lastSkinsSignature = Self.skinsFolderSignature()
        startSkinFolderWatch()
    }

    // MARK: Awake controls

    func reloadSkinLibrary() {
        CharacterSpriteStore.shared.invalidate()
        let loaded = PetSkinLibrary.load()
        availableSkins = loaded.isEmpty ? [.fallback] : loaded
        if !availableSkins.contains(where: { $0.id == selectedSkinID }) {
            selectedSkinID = availableSkins[0].id
        }
        lastSkinsSignature = Self.skinsFolderSignature()
    }

    private func startSkinFolderWatch() {
        skinWatchTimer?.invalidate()
        skinWatchTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadSkinsIfFolderChanged()
            }
        }
    }

    private func reloadSkinsIfFolderChanged() {
        let signature = Self.skinsFolderSignature()
        guard signature != lastSkinsSignature else { return }
        reloadSkinLibrary()
    }

    private static func skinsFolderSignature() -> String {
        guard let directory = PetSkinLibrary.userDirectory else { return "" }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return directory.path }
        let parts = items.map { url -> String in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return "\(url.lastPathComponent):\(date.timeIntervalSince1970)"
        }.sorted()
        return parts.joined(separator: "|")
    }

    func setKeepAwake(_ enabled: Bool) {
        if enabled {
            startManualAwake()
        } else {
            stopKeepingAwake()
        }
    }

    func startManualAwake() {
        cancelPendingImmediateSleepRequest()
        manualAwake = true
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionEndDate = nil
        sessionCompletionAction = nil
        remainingSeconds = nil
        isFocusSession = false
        holdStartUptime = ProcessInfo.processInfo.systemUptime
        hasCapTripped = false
        isPausedByBatteryFloor = false

        startPowerAssertions(labels: assertionLabels())
        guard isKeepingAwake else { return }
        if !isPausedByBatteryFloor {
            statusMessage = L10n.format("%@ is keeping your Mac awake", characterName)
            setMood(isBreakDue ? .breakReminder : .working)
        }
    }

    func startFocusSession(confirmedImmediateSleep: Bool = false) {
        if completionAction == .sleepImmediately && !confirmedImmediateSleep {
            statusMessage = L10n.text("Confirm immediate sleep before starting this session.")
            return
        }

        cancelPendingImmediateSleepRequest()
        let minutes = min(max(selectedMinutes, 15), 240)
        holdStartUptime = ProcessInfo.processInfo.systemUptime
        hasCapTripped = false
        isPausedByBatteryFloor = false

        startPowerAssertions(labels: assertionLabels(forceFocusMinutes: minutes, includeManual: false))
        guard isKeepingAwake else { return }

        manualAwake = false
        sessionTimer?.invalidate()
        sessionEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sessionCompletionAction = completionAction
        isFocusSession = true
        if !isPausedByBatteryFloor {
            statusMessage = L10n.format("Focus session started - %d min", minutes)
            setMood(isBreakDue ? .breakReminder : .working)
        }
        updateCountdown()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCountdown()
            }
        }
    }

    func stopKeepingAwake() {
        cancelPendingImmediateSleepRequest()
        let wasRunning = isKeepingAwake || isFocusSession || manualAwake || !agentSessions.isEmpty
        sessionTimer?.invalidate()
        sessionTimer = nil
        breakTimer?.invalidate()
        breakTimer = nil
        isBreakDue = false
        stopHeartbeatTimer()
        agentLeaseTimer?.invalidate()
        agentLeaseTimer = nil
        agentSessions.removeAll()
        dismissedWaitingIDs.removeAll()
        manualAwake = false
        sessionEndDate = nil
        sessionCompletionAction = nil
        remainingSeconds = nil
        isFocusSession = false
        holdStartUptime = nil
        hasCapTripped = false
        isPausedByBatteryFloor = false
        powerKeeper.end()
        isKeepingAwake = false
        powerWarning = nil
        updateDiagnostics()

        guard wasRunning else { return }
        statusMessage = L10n.format("%@'s shift is over - your Mac is back to its normal sleep settings", characterName)
        setTemporaryMood(.resting, duration: 1.8, then: .idle)
    }

    func shutdown() {
        skinWatchTimer?.invalidate()
        skinWatchTimer = nil
        stopWebhookServer()
        stopKeepingAwake()
        powerKeeper.shutdown()
        powerSourceMonitor.shutdown()
        stopHeartbeatTimer()
    }

    // MARK: Local agent bridge

    /// Accepts an opt-in local URL event from a CLI hook or companion script:
    /// sweetnosleep://agent/start|heartbeat|waiting|done|failed?session=<id>[&reason=<text>]
    func handleAgentURL(_ url: URL) {
        guard agentBridgeEnabled,
              url.scheme?.lowercased() == "sweetnosleep",
              url.host?.lowercased() == "agent",
              let action = url.pathComponents.dropFirst().first
        else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let sessionID = components?.queryItems?.first(where: { $0.name == "session" })?.value,
              !sessionID.isEmpty,
              sessionID.count <= 120
        else { return }
        let reason = components?.queryItems?.first(where: { $0.name == "reason" })?.value

        handleAgentEvent(action: action, sessionID: sessionID, reason: reason)
    }

    /// Shared agent-event pipeline for both delivery channels: the
    /// sweetnosleep:// URL scheme and the loopback webhook server.
    func handleAgentEvent(action: String, sessionID: String, reason: String?) {
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReason: String? = {
            guard let value = trimmedReason, !value.isEmpty else { return nil }
            return String(value.prefix(200))
        }()
        switch action.lowercased() {
        case "start":
            renewAgentSession(sessionID: sessionID)
            statusMessage = L10n.text("An AI agent reported that work has started.")
        case "heartbeat":
            // Unknown sessions are ignored on every channel (webhook semantics).
            // Use `start` to open a lease; a stray heartbeat must not create one.
            guard agentSessions[sessionID] != nil else { return }
            renewAgentSession(sessionID: sessionID)
        case "waiting":
            markAgentWaiting(sessionID: sessionID, reason: reason)
        case "done":
            finishAgentSession(sessionID: sessionID, failed: false)
        case "failed":
            finishAgentSession(sessionID: sessionID, failed: true)
        default:
            return
        }
    }

    // MARK: Loopback webhook (F3)

    func regenerateWebhookToken() {
        agentWebhookToken = Self.makeWebhookToken()
        // A running listener still holds the previous token; bounce it so the
        // token shown in Settings is the one it validates (issue #21 audit).
        if agentWebhookEnabled {
            startWebhookServer()
        }
    }

    private static func makeWebhookToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func isValidWebhookToken(_ token: String) -> Bool {
        guard token.count == 32 else { return false }
        return token.allSatisfy { $0.isHexDigit }
    }

    private func startWebhookServer() {
        stopWebhookServer()
        agentWebhookError = nil
        let server = AgentWebhookServer(
            port: 18290,
            token: agentWebhookToken,
            onEvent: { [weak self] action, sessionID, reason in
                guard let self else { return }
                guard self.agentBridgeEnabled else { return }
                guard !sessionID.isEmpty, sessionID.count <= 120 else { return }
                self.handleAgentEvent(action: action, sessionID: sessionID, reason: reason)
            },
            onError: { [weak self] message in
                self?.agentWebhookError = message
            }
        )
        agentWebhookServer = server
        server.start()
    }

    private func stopWebhookServer() {
        agentWebhookServer?.stop()
        agentWebhookServer = nil
        agentWebhookError = nil
    }


    /// Closes the waiting bubble for the sessions that currently wait. The
    /// agent keeps waiting in its own window: this only hides the prompt.
    func dismissWaitingCue() {
        dismissedWaitingIDs.formUnion(agentSessions.filter { $0.value.isWaiting }.map(\.key))
    }

    /// A local emergency action; other manual or timed sources remain active.
    func endAgentSessions() {
        guard !agentSessions.isEmpty else { return }
        agentSessions.removeAll()
        dismissedWaitingIDs.removeAll()
        agentLeaseTimer?.invalidate()
        agentLeaseTimer = nil
        finishAwakeIfNoOtherSource(message: L10n.text("Agent sessions were stopped manually."))
    }

    private func renewAgentSession(sessionID: String, status: AgentSessionStatus = .working, reason: String? = nil) {
        cancelPendingImmediateSleepRequest()
        let now = Date()
        let startedAt = agentSessions[sessionID]?.startedAt ?? now
        let wasWaiting = agentSessions[sessionID]?.isWaiting ?? false
        let lease = status == .waiting ? Self.waitingLeaseTimeout : Self.agentLeaseTimeout
        agentSessions[sessionID] = AgentSessionState(
            status: status,
            startedAt: startedAt,
            lastActivityAt: now,
            expiry: now.addingTimeInterval(lease),
            reason: status == .waiting ? reason : nil
        )
        if status == .working {
            // The session moved on: its bubble may appear again next time.
            dismissedWaitingIDs.remove(sessionID)
        }

        if agentLeaseTimer == nil {
            agentLeaseTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pruneExpiredAgentSessions()
                }
            }
        }

        if holdStartUptime == nil {
            holdStartUptime = ProcessInfo.processInfo.systemUptime
            hasCapTripped = false
        }

        if !isKeepingAwake {
            startPowerAssertions(labels: assertionLabels(includeAgent: true))
        } else {
            syncAssertionName()
        }

        let resumedFromWaiting = wasWaiting && status == .working
        if isKeepingAwake,
           !isFocusSession,
           !manualAwake,
           !isPausedByBatteryFloor,
           (mood == .idle || mood == .resting || mood == .waitingForApproval || resumedFromWaiting) {
            setMood(baseMood())
        }
        if resumedFromWaiting {
            schedulePlayfulMoment()
        }
    }

    /// Marks a session as waiting for input. An unknown session is accepted as
    /// well, so a hook that only reports questions still lights the cue.
    private func markAgentWaiting(sessionID: String, reason: String?) {
        let cleanReason = reason.map(Self.sanitizedReason)
        let alreadyWaiting = agentSessions[sessionID]?.isWaiting ?? false
        renewAgentSession(sessionID: sessionID, status: .waiting, reason: cleanReason)
        guard !alreadyWaiting else { return }

        // Waiting outranks playful moments and roaming: the pet stays put and
        // asks for the answer.
        playfulTimer?.invalidate()
        playfulTimer = nil
        statusMessage = L10n.text("An agent is waiting for your approval.")
        if !isFocusSession, !manualAwake, !isPausedByBatteryFloor, mood != .dragging {
            setMood(.waitingForApproval)
        }
    }

    private func finishAgentSession(sessionID: String, failed: Bool) {
        guard agentSessions.removeValue(forKey: sessionID) != nil else { return }
        dismissedWaitingIDs.remove(sessionID)
        if agentSessions.isEmpty {
            agentLeaseTimer?.invalidate()
            agentLeaseTimer = nil
        }
        setMoodIfWaitingIsOver()
        let message = failed
            ? L10n.text("The AI agent failed.")
            : L10n.text("The AI agent reported completion.")
        if isKeepingAwake, !agentSessions.isEmpty {
            syncAssertionName()
        }
        finishAwakeIfNoOtherSource(message: message)
    }

    private func pruneExpiredAgentSessions() {
        let now = Date()
        let expired = agentSessions.filter { $0.value.expiry <= now }.map(\.key)
        guard !expired.isEmpty else { return }

        for sessionID in expired {
            agentSessions.removeValue(forKey: sessionID)
            dismissedWaitingIDs.remove(sessionID)
        }
        if agentSessions.isEmpty {
            agentLeaseTimer?.invalidate()
            agentLeaseTimer = nil
        }
        setMoodIfWaitingIsOver()

        let message = agentSessions.isEmpty
            ? L10n.text("The AI agent connection was lost - sleep protection ended after timeout")
            : L10n.text("One agent heartbeat expired - other sessions are still active")
        if isKeepingAwake, !agentSessions.isEmpty {
            syncAssertionName()
        }
        finishAwakeIfNoOtherSource(message: message)
    }

    /// Keeps only the reason text that is safe to show: one line, no control
    /// characters, at most 200 characters.
    private static func sanitizedReason(_ reason: String) -> String {
        let flattened = reason
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(flattened.prefix(200))
    }

    /// Returns the pet to its resting expression once nobody waits any more.
    private func setMoodIfWaitingIsOver() {
        guard !hasWaitingAgent else { return }
        if mood == .waitingForApproval {
            setMood(baseMood())
            schedulePlayfulMoment()
        }
    }

    /// The mood the pet falls back to when nothing temporary is going on.
    /// An agent waiting for input always wins; then break reminders; then work.
    func baseMood() -> KiwiMood {
        if hasWaitingAgent { return .waitingForApproval }
        if isBreakDue { return .breakReminder }
        if isKeepingAwake || isFocusSession || manualAwake { return .working }
        return .idle
    }

    private func finishAwakeIfNoOtherSource(message: String) {
        guard !manualAwake, !isFocusSession, agentSessions.isEmpty else {
            statusMessage = L10n.format("%@ - other sessions are still protected", message)
            return
        }

        sessionTimer?.invalidate()
        sessionTimer = nil
        breakTimer?.invalidate()
        breakTimer = nil
        stopHeartbeatTimer()
        isBreakDue = false
        sessionEndDate = nil
        sessionCompletionAction = nil
        remainingSeconds = nil
        holdStartUptime = nil
        hasCapTripped = false
        isPausedByBatteryFloor = false
        powerKeeper.end()
        isKeepingAwake = false
        powerWarning = nil
        statusMessage = L10n.format("%@ - your Mac is back to its normal sleep settings", message)
        setTemporaryMood(.celebrating, duration: 1.6, then: .idle)
        updateDiagnostics()
    }

    // MARK: Pet interactions

    func poke() {
        guard mood != .dragging else { return }
        // Ignore taps right after system wake: the user was waking the Mac,
        // not tapping the pet.
        if let lastWake = lastSystemWakeDate, Date().timeIntervalSince(lastWake) < 3.0 { return }
        statusMessage = isKeepingAwake
            ? L10n.format("%@ is on duty and protecting this session.", characterName)
            : L10n.format("Should %@ get to work too - or take a break?", characterName)
        setTemporaryMood(.celebrating, duration: 2.0, then: baseMood())
    }

    func beginDragging() {
        moodTimer?.invalidate()
        mood = .dragging
    }

    func endDragging() {
        mood = baseMood()
    }

    @discardableResult
    func beginWandering() -> Bool {
        guard isPetVisible,
              roamingEnabled,
              animationsEnabled,
              !isBreakDue,
              !hasWaitingAgent,
              (mood == .idle || mood == .working)
        else { return false }
        mood = .walking
        return true
    }

    func endWandering() {
        guard mood == .walking else { return }
        mood = baseMood()
    }

    func dismissBreakReminder(snoozeMinutes: Int? = nil) {
        guard isBreakDue else { return }
        isBreakDue = false
        setMood(baseMood())

        let delayMinutes = max(snoozeMinutes ?? breakIntervalMinutes, 1)
        statusMessage = snoozeMinutes == nil
            ? L10n.format("Nice break - I'll gently remind you again in %d min", delayMinutes)
            : L10n.format("Okay - I'll remind you again in %d min", delayMinutes)
        scheduleBreakReminder(after: TimeInterval(delayMinutes * 60))
        schedulePlayfulMoment()
    }

    // MARK: Private helpers

    private func cancelPendingImmediateSleepRequest() {
        pendingImmediateSleepToken = nil
    }

    private func assertionLabels(
        forceFocusMinutes: Int? = nil,
        includeManual: Bool? = nil,
        includeAgent: Bool? = nil
    ) -> (reason: String, human: String) {
        let focus = forceFocusMinutes != nil || isFocusSession
        let minutes = forceFocusMinutes ?? selectedMinutes
        let manual = includeManual ?? manualAwake
        let agent = includeAgent ?? !agentSessions.isEmpty
        var tags: [String] = []
        if focus { tags.append("focus") }
        if manual { tags.append("manual") }
        if agent { tags.append("agent") }
        if tags.isEmpty { tags.append("manual") }
        let joined = tags.joined(separator: "+")
        let reason = "Sweet No Sleep - \(joined)"
        let human: String
        if focus && tags.count == 1 {
            human = L10n.format("Sweet No Sleep - focus session (%d min)", minutes)
        } else if agent && tags.count == 1 {
            human = L10n.text("Sweet No Sleep - AI agent work in progress")
        } else if manual && tags.count == 1 {
            human = L10n.text("Sweet No Sleep - manual keep-awake mode")
        } else {
            human = L10n.format("Sweet No Sleep - %@ keep-awake", joined)
        }
        return (reason, human)
    }

    /// Renames the live IOKit assertion so pmset reflects the current source class.
    private func syncAssertionName() {
        guard isKeepingAwake, !isPausedByBatteryFloor else {
            updateDiagnostics()
            return
        }
        let labels = assertionLabels()
        _ = powerKeeper.begin(
            reason: labels.reason,
            humanReadableReason: labels.human,
            keepDisplayOn: keepDisplayAwake
        )
        updateDiagnostics()
    }

    private func startPowerAssertions(labels: (reason: String, human: String)) {
        guard !isKeepingAwake else {
            syncAssertionName()
            return
        }
        powerWarning = nil

        let currentPS = powerSourceMonitor.currentStatus
        if batteryFloorPercent > 0,
           currentPS.hasInternalBattery,
           !currentPS.isPluggedIn,
           currentPS.batteryPercent <= batteryFloorPercent {
            isKeepingAwake = true
            isPausedByBatteryFloor = true
            powerWarning = L10n.format("Battery below %d%% - assertions released.", batteryFloorPercent)
            statusMessage = L10n.format("Battery is below %d%% - plug in to enable sleep protection.", batteryFloorPercent)
            powerKeeper.setLastPowerEvent(L10n.format("Battery below %d%% - assertions released.", batteryFloorPercent))
            startHeartbeatTimer()
            scheduleBreakReminder()
            setTemporaryMood(.resting, duration: 1.8, then: .resting)
            updateDiagnostics()
            return
        }

        let result = powerKeeper.begin(
            reason: labels.reason,
            humanReadableReason: labels.human,
            keepDisplayOn: keepDisplayAwake
        )
        guard result.success else {
            manualAwake = false
            isKeepingAwake = false
            isFocusSession = false
            sessionTimer?.invalidate()
            sessionTimer = nil
            breakTimer?.invalidate()
            breakTimer = nil
            stopHeartbeatTimer()
            isBreakDue = false
            sessionEndDate = nil
            sessionCompletionAction = nil
            remainingSeconds = nil
            holdStartUptime = nil
            powerWarning = result.message
            statusMessage = result.message ?? L10n.text("Could not enable sleep protection.")
            setTemporaryMood(.resting, duration: 1.8, then: .idle)
            updateDiagnostics()
            return
        }

        isKeepingAwake = true
        isPausedByBatteryFloor = false
        powerWarning = result.message
        startHeartbeatTimer()
        scheduleBreakReminder()
        updateDiagnostics()
    }

    private func refreshPowerAssertions() {
        let labels = assertionLabels()
        let result = powerKeeper.begin(
            reason: labels.reason,
            humanReadableReason: labels.human,
            keepDisplayOn: keepDisplayAwake
        )
        guard result.success else {
            sessionTimer?.invalidate()
            sessionTimer = nil
            breakTimer?.invalidate()
            breakTimer = nil
            stopHeartbeatTimer()
            isBreakDue = false
            sessionEndDate = nil
            sessionCompletionAction = nil
            remainingSeconds = nil
            isFocusSession = false
            manualAwake = false
            isKeepingAwake = false
            holdStartUptime = nil
            powerWarning = result.message
            statusMessage = result.message ?? L10n.text("Could not refresh sleep protection.")
            setTemporaryMood(.resting, duration: 1.8, then: .idle)
            updateDiagnostics()
            return
        }
        powerWarning = result.message
        updateDiagnostics()
    }

    private func handlePowerSourceChange(_ status: PowerSourceStatus) {
        updateDiagnostics()
        guard isKeepingAwake else { return }

        if batteryFloorPercent > 0,
           status.hasInternalBattery,
           !status.isPluggedIn,
           status.batteryPercent <= batteryFloorPercent {
            if !isPausedByBatteryFloor {
                isPausedByBatteryFloor = true
                powerKeeper.pauseAssertions(eventDescription: L10n.format("Battery below %d%% - assertions released.", batteryFloorPercent))
                powerWarning = L10n.format("Battery below %d%% - assertions released.", batteryFloorPercent)
                statusMessage = L10n.format("Battery below %d%% - sleep protection paused to save battery.", batteryFloorPercent)
                setTemporaryMood(.resting, duration: 1.8, then: .resting)
            }
        } else {
            if isPausedByBatteryFloor {
                isPausedByBatteryFloor = false
                powerWarning = nil
                let res = powerKeeper.resumeAssertions(
                    keepDisplayOn: keepDisplayAwake,
                    eventDescription: L10n.text("Power restored: assertions resumed")
                )
                if res.success {
                    statusMessage = L10n.text("Power restored - sleep protection resumed.")
                    setMood(isBreakDue ? .breakReminder : .working)
                } else {
                    powerWarning = res.message
                }
            }
        }
    }

    private func checkAwakeCap() {
        guard isKeepingAwake,
              continuousAwakeCapHours > 0,
              !hasCapTripped,
              let startUptime = holdStartUptime
        else { return }

        let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
        let capSeconds = Double(continuousAwakeCapHours * 3600)
        if elapsed >= capSeconds {
            hasCapTripped = true
            let hours = continuousAwakeCapHours
            stopKeepingAwake()
            powerWarning = L10n.format("Awake cap reached (%d h).", hours)
            statusMessage = L10n.format("Continuous awake cap reached (%d hours) - sleep protection stopped to save power.", hours)
            powerKeeper.setLastPowerEvent(L10n.text("Awake cap reached: assertions released"))
        }
    }

    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.checkAwakeCap()
                self.updateDiagnostics()
            }
        }
    }

    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func awakeSourcesDescription() -> String {
        var parts: [String] = []
        if isFocusSession { parts.append(L10n.text("focus")) }
        if manualAwake { parts.append(L10n.text("manual")) }
        if !agentSessions.isEmpty {
            parts.append(L10n.format("agent × %d", agentSessions.count))
        }
        return parts.isEmpty ? L10n.text("none") : parts.joined(separator: ", ")
    }

    private func updateDiagnostics() {
        let seconds = max(0, Int(ceil(powerKeeper.nextRearmDate?.timeIntervalSinceNow ?? 0)))
        let powerSource = powerSourceMonitor.currentStatus
        diagnostics = PowerDiagnostics(
            systemAssertionID: powerKeeper.systemAssertionID,
            displayAssertionID: powerKeeper.displayAssertionID,
            isSystemActive: powerKeeper.isSystemAsserted,
            isDisplayActive: powerKeeper.isDisplayAsserted,
            secondsUntilRearm: (powerKeeper.isSystemAsserted || powerKeeper.isDisplayAsserted) ? seconds : 0,
            batteryDescription: powerSource.descriptionText,
            lastPowerEvent: powerKeeper.lastPowerEvent,
            awakeSources: awakeSourcesDescription()
        )
    }

    private func updateCountdown() {
        guard let sessionEndDate else { return }
        let secondsLeft = Int(ceil(sessionEndDate.timeIntervalSinceNow))
        guard secondsLeft > 0 else {
            finishFocusSession()
            return
        }
        remainingSeconds = secondsLeft
    }

    private func finishFocusSession() {
        let shouldSleepImmediately = sessionCompletionAction == .sleepImmediately
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionEndDate = nil
        sessionCompletionAction = nil
        remainingSeconds = nil
        isFocusSession = false
        let otherWorkRemains = manualAwake || !agentSessions.isEmpty
        if otherWorkRemains {
            isKeepingAwake = true
            statusMessage = activeAgentCount > 0
                ? L10n.text("Timer finished - an AI agent is still working")
                : L10n.text("Timer finished - manual sleep protection is still on")
        } else {
            powerKeeper.end()
            stopHeartbeatTimer()
            breakTimer?.invalidate()
            breakTimer = nil
            isBreakDue = false
            isKeepingAwake = false
            holdStartUptime = nil
            hasCapTripped = false
            isPausedByBatteryFloor = false
            powerWarning = nil
            statusMessage = L10n.text("Goal reached - the session is complete")
        }

        setTemporaryMood(.celebrating, duration: 2.2, then: .idle)
        updateDiagnostics()

        guard shouldSleepImmediately, !otherWorkRemains else { return }
        // Let the release of our assertions reach power management first.
        let sleepToken = UUID()
        pendingImmediateSleepToken = sleepToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.pendingImmediateSleepToken == sleepToken else { return }
            self.pendingImmediateSleepToken = nil
            // A new manual, focus or agent session can begin during the short
            // delay needed to release the IOKit assertion. Never sleep through it.
            guard !self.isKeepingAwake,
                  !self.isFocusSession,
                  !self.manualAwake,
                  self.agentSessions.isEmpty
            else { return }
            guard let error = self.powerKeeper.requestImmediateSleep() else { return }
            self.statusMessage = L10n.format("Session ended, but sleep did not start: %@", error)
            self.powerWarning = error
            self.updateDiagnostics()
        }
    }

    private func schedulePlayfulMoment() {
        playfulTimer?.invalidate()
        playfulTimer = nil
        guard isKeepingAwake,
              isPetVisible,
              animationsEnabled,
              playfulMomentsEnabled,
              !isBreakDue,
              !hasWaitingAgent,
              playfulDancingWeight + playfulStretchingWeight + playfulCuriousWeight > 0
        else { return }

        let preferredInterval = Double(min(max(playfulMomentIntervalSeconds, 15), 120))
        let minimumDelay = max(60, preferredInterval * 0.9)
        let maximumDelay = min(120, preferredInterval * 1.1)
        let delay = TimeInterval.random(in: minimumDelay...maximumDelay)
        playfulTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playfulTimer = nil
                guard self.isKeepingAwake,
                      self.isPetVisible,
                      self.animationsEnabled,
                      self.playfulMomentsEnabled,
                      !self.isBreakDue,
                      !self.hasWaitingAgent,
                      (self.mood == .working || self.mood == .idle)
                else {
                    self.schedulePlayfulMoment()
                    return
                }

                guard let moment = self.weightedPlayfulMood() else { return }
                let duration = TimeInterval.random(in: 3.4...5.2)
                self.setTemporaryMood(moment, duration: duration, then: .working)
                self.schedulePlayfulMoment()
            }
        }
    }

    private func weightedPlayfulMood() -> KiwiMood? {
        let choices: [(mood: KiwiMood, weight: Int)] = [
            (.dancing, max(playfulDancingWeight, 0)),
            (.stretching, max(playfulStretchingWeight, 0)),
            (.curious, max(playfulCuriousWeight, 0))
        ]
        let totalWeight = choices.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        var selection = Int.random(in: 1...totalWeight)
        for choice in choices {
            selection -= choice.weight
            if selection <= 0 { return choice.mood }
        }
        return nil
    }

    private func scheduleBreakReminder(after delay: TimeInterval? = nil) {
        breakTimer?.invalidate()
        breakTimer = nil
        guard breakRemindersEnabled, isKeepingAwake, !isBreakDue else { return }

        let interval = delay ?? TimeInterval(breakIntervalMinutes * 60)
        breakTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.breakTimer = nil
                guard self.isKeepingAwake, self.breakRemindersEnabled else { return }
                // Never cover the agent's question with a break reminder: come
                // back when the waiting cue is resolved.
                if self.hasWaitingAgent {
                    self.scheduleBreakReminder(after: 30)
                    return
                }
                self.isBreakDue = true
                self.playfulTimer?.invalidate()
                self.playfulTimer = nil
                self.statusMessage = L10n.text("Time to look away from the code for a moment.")
                self.setMood(.breakReminder)
            }
        }
    }

    private func setMood(_ newMood: KiwiMood) {
        moodTimer?.invalidate()
        moodTimer = nil
        mood = newMood
    }

    private func setTemporaryMood(_ newMood: KiwiMood, duration: TimeInterval, then finalMood: KiwiMood) {
        moodTimer?.invalidate()
        mood = newMood
        moodTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let fallback = self.isKeepingAwake && finalMood == .idle ? .working : finalMood
                self.mood = self.baseMood() == .idle ? fallback : self.baseMood()
            }
        }
    }

    private enum Key {
        static let selectedMinutes = "session.selectedMinutes"
        static let skin = "pet.skin"
        static let petSize = "pet.size"
        static let keepDisplayAwake = "power.keepDisplayAwake"
        static let batteryFloorPercent = "power.batteryFloorPercent"
        static let continuousAwakeCapHours = "power.continuousAwakeCapHours"
        static let completionAction = "session.completionAction"
        static let resumeOnLaunch = "power.resumeOnLaunch"
        static let agentBridgeEnabled = "agentBridge.enabled"
        static let agentWebhookEnabled = "agent.webhookEnabled"
        static let agentWebhookToken = "agent.webhookToken"
        static let agentIndicatorEnabled = "agentBridge.indicatorEnabled"
        static let petVisible = "pet.visible"
        static let alwaysOnTop = "pet.alwaysOnTop"
        static let roamingEnabled = "pet.roamingEnabled"
        static let animationsEnabled = "pet.animationsEnabled"
        static let playfulMomentsEnabled = "pet.playfulMomentsEnabled"
        static let playfulMomentIntervalSeconds = "pet.playfulMomentIntervalSeconds"
        static let playfulDancingWeight = "pet.playfulDancingWeight"
        static let playfulStretchingWeight = "pet.playfulStretchingWeight"
        static let playfulCuriousWeight = "pet.playfulCuriousWeight"
        static let breakRemindersEnabled = "breakReminders.enabled"
        static let breakIntervalMinutes = "breakReminders.intervalMinutes"
    }
}

extension TimeInterval {
    var shortCountdown: String {
        let total = max(Int(self), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
