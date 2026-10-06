import Combine
import Foundation
import SwiftUI

// MARK: - Companion and session models

enum KiwiMood: Equatable {
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
}

enum SessionCompletionAction: String, CaseIterable, Identifiable, Hashable {
    case allowNormalSleep
    case sleepImmediately

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allowNormalSleep: "Разрешить обычный сон"
        case .sleepImmediately: "Сразу отправить Mac в сон"
        }
    }

    var detail: String {
        switch self {
        case .allowNormalSleep:
            "Снять защиту от сна. macOS уснёт по своим настройкам энергосбережения."
        case .sleepImmediately:
            "После подтверждённой сессии Киви отправит запрос на немедленный сон."
        }
    }
}

/// Shared application state for the menu, settings, pet window and power keeper.
@MainActor
final class SweetNoSleepModel: ObservableObject {
    static let shared = SweetNoSleepModel()

    private let defaults = UserDefaults.standard
    private let powerKeeper = PowerKeeper()
    private var sessionTimer: Timer?
    private var moodTimer: Timer?
    private var playfulTimer: Timer?
    private var breakTimer: Timer?
    private var sessionEndDate: Date?
    private var sessionCompletionAction: SessionCompletionAction?
    private var manualAwake = false
    private var agentLeases: [String: Date] = [:]
    private var agentLeaseTimer: Timer?
    private static let agentLeaseTimeout: TimeInterval = 180

    @Published private(set) var isKeepingAwake = false {
        didSet {
            if oldValue != isKeepingAwake { schedulePlayfulMoment() }
        }
    }
    @Published private(set) var isFocusSession = false
    @Published private(set) var activeAgentCount = 0
    @Published private(set) var remainingSeconds: Int?
    @Published private(set) var powerWarning: String?
    @Published var statusMessage = "Киви готов составить компанию"
    @Published private(set) var mood: KiwiMood = .idle

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

    @Published var breakRemindersEnabled: Bool {
        didSet {
            defaults.set(breakRemindersEnabled, forKey: Key.breakRemindersEnabled)
            if breakRemindersEnabled { scheduleBreakReminder() }
            else {
                breakTimer?.invalidate()
                breakTimer = nil
                if isBreakDue {
                    isBreakDue = false
                    setMood(isKeepingAwake ? .working : .idle)
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
        petSize = min(max(savedSize, 90), 170)
        keepDisplayAwake = defaults.object(forKey: Key.keepDisplayAwake) as? Bool ?? false
        resumeKeepAwakeOnLaunch = defaults.object(forKey: Key.resumeOnLaunch) as? Bool ?? false
        agentBridgeEnabled = defaults.object(forKey: Key.agentBridgeEnabled) as? Bool ?? false
        isPetVisible = defaults.object(forKey: Key.petVisible) as? Bool ?? true
        alwaysOnTop = defaults.object(forKey: Key.alwaysOnTop) as? Bool ?? true
        roamingEnabled = defaults.object(forKey: Key.roamingEnabled) as? Bool ?? false
        animationsEnabled = defaults.object(forKey: Key.animationsEnabled) as? Bool ?? true
        playfulMomentsEnabled = defaults.object(forKey: Key.playfulMomentsEnabled) as? Bool ?? true
        breakRemindersEnabled = defaults.object(forKey: Key.breakRemindersEnabled) as? Bool ?? true
        breakIntervalMinutes = min(max(defaults.object(forKey: Key.breakIntervalMinutes) as? Int ?? 25, 10), 60)

        powerKeeper.onFailure = { [weak self] message in
            guard let self else { return }
            self.sessionTimer?.invalidate()
            self.sessionTimer = nil
            self.breakTimer?.invalidate()
            self.breakTimer = nil
            self.isBreakDue = false
            self.sessionEndDate = nil
            self.sessionCompletionAction = nil
            self.remainingSeconds = nil
            self.isFocusSession = false
            self.manualAwake = false
            self.isKeepingAwake = false
            self.powerWarning = message
            self.statusMessage = message
            self.setTemporaryMood(.resting, duration: 1.8, then: .idle)
        }
        schedulePlayfulMoment()
    }

    // MARK: Awake controls

    func reloadSkinLibrary() {
        let loaded = PetSkinLibrary.load()
        availableSkins = loaded.isEmpty ? [.fallback] : loaded
        if !availableSkins.contains(where: { $0.id == selectedSkinID }) {
            selectedSkinID = availableSkins[0].id
        }
    }

    func setKeepAwake(_ enabled: Bool) {
        if enabled {
            startManualAwake()
        } else {
            stopKeepingAwake()
        }
    }

    func startManualAwake() {
        manualAwake = true
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionEndDate = nil
        sessionCompletionAction = nil
        remainingSeconds = nil
        isFocusSession = false
        startPowerAssertions(reason: "Sweet No Sleep — ручной режим")
        guard isKeepingAwake else { return }
        statusMessage = "Киви следит, чтобы Mac не уснул"
        setMood(.working)
    }

    func startFocusSession(confirmedImmediateSleep: Bool = false) {
        if completionAction == .sleepImmediately && !confirmedImmediateSleep {
            statusMessage = "Подтвердите немедленный сон перед запуском сессии"
            return
        }

        let minutes = min(max(selectedMinutes, 15), 240)
        startPowerAssertions(reason: "Sweet No Sleep — фокус-сессия, \(minutes) мин")
        guard isKeepingAwake else { return }

        manualAwake = false
        sessionTimer?.invalidate()
        sessionEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sessionCompletionAction = completionAction
        isFocusSession = true
        statusMessage = "Фокус-сессия началась · \(minutes) мин"
        setMood(.working)
        updateCountdown()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
    }

    func stopKeepingAwake() {
        let wasRunning = isKeepingAwake || isFocusSession || manualAwake || !agentLeases.isEmpty
        sessionTimer?.invalidate()
        sessionTimer = nil
        breakTimer?.invalidate()
        breakTimer = nil
        isBreakDue = false
        agentLeaseTimer?.invalidate()
        agentLeaseTimer = nil
        agentLeases.removeAll()
        activeAgentCount = 0
        manualAwake = false
        sessionEndDate = nil
        sessionCompletionAction = nil
        remainingSeconds = nil
        isFocusSession = false
        powerKeeper.end()
        isKeepingAwake = false
        powerWarning = nil

        guard wasRunning else { return }
        statusMessage = "Киви закончил смену · Mac снова следует настройкам сна"
        setTemporaryMood(.resting, duration: 1.8, then: .idle)
    }

    // MARK: Local agent bridge

    /// Accepts an opt-in local URL event from a CLI hook or companion script:
    /// sweetnosleep://agent/start|heartbeat|done|failed?session=<stable-id>
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

        switch action.lowercased() {
        case "start":
            renewAgentLease(sessionID: sessionID)
            statusMessage = "AI-агент сообщил о начале работы"
        case "heartbeat":
            guard agentLeases[sessionID] != nil else { return }
            renewAgentLease(sessionID: sessionID)
        case "done":
            finishAgentLease(sessionID: sessionID, failed: false)
        case "failed":
            finishAgentLease(sessionID: sessionID, failed: true)
        default:
            return
        }
    }

    /// A local emergency action; other manual or timed sources remain active.
    func endAgentSessions() {
        guard !agentLeases.isEmpty else { return }
        agentLeases.removeAll()
        agentLeaseTimer?.invalidate()
        agentLeaseTimer = nil
        activeAgentCount = 0
        finishAwakeIfNoOtherSource(message: "Связь с агентами снята вручную")
    }

    private func renewAgentLease(sessionID: String) {
        agentLeases[sessionID] = Date().addingTimeInterval(Self.agentLeaseTimeout)
        if activeAgentCount != agentLeases.count {
            activeAgentCount = agentLeases.count
        }

        if agentLeaseTimer == nil {
            agentLeaseTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                self?.pruneExpiredAgentLeases()
            }
        }

        if !isKeepingAwake {
            startPowerAssertions(reason: "Sweet No Sleep — работа AI-агента")
        }
        if isKeepingAwake {
            powerWarning = nil
            if !isFocusSession && !manualAwake { setMood(.working) }
        }
    }

    private func finishAgentLease(sessionID: String, failed: Bool) {
        guard agentLeases.removeValue(forKey: sessionID) != nil else { return }
        activeAgentCount = agentLeases.count
        if agentLeases.isEmpty {
            agentLeaseTimer?.invalidate()
            agentLeaseTimer = nil
        }
        let message = failed ? "AI-агент завершился с ошибкой" : "AI-агент сообщил о завершении"
        finishAwakeIfNoOtherSource(message: message)
    }

    private func pruneExpiredAgentLeases() {
        let now = Date()
        let expired = agentLeases.filter { $0.value <= now }.map(\.key)
        guard !expired.isEmpty else { return }

        for sessionID in expired { agentLeases.removeValue(forKey: sessionID) }
        activeAgentCount = agentLeases.count
        if agentLeases.isEmpty {
            agentLeaseTimer?.invalidate()
            agentLeaseTimer = nil
        }

        let message = agentLeases.isEmpty
            ? "Связь с AI-агентом потеряна · защита снята по таймауту"
            : "Один heartbeat агента истёк · другие сессии продолжаются"
        finishAwakeIfNoOtherSource(message: message)
    }

    private func finishAwakeIfNoOtherSource(message: String) {
        guard !manualAwake, !isFocusSession, agentLeases.isEmpty else {
            statusMessage = message + " · другие сессии всё ещё защищены"
            return
        }

        sessionTimer?.invalidate()
        sessionTimer = nil
        breakTimer?.invalidate()
        breakTimer = nil
        isBreakDue = false
        sessionEndDate = nil
        sessionCompletionAction = nil
        remainingSeconds = nil
        powerKeeper.end()
        isKeepingAwake = false
        powerWarning = nil
        statusMessage = message + " · Mac вернулся к обычным настройкам сна"
        setTemporaryMood(.celebrating, duration: 1.6, then: .idle)
    }

    // MARK: Pet interactions

    func poke() {
        guard mood != .dragging else { return }
        statusMessage = isKeepingAwake ? "Киви на связи и бережёт сессию" : "Киви тоже за работу — или на отдых?"
        setTemporaryMood(.celebrating, duration: 1.25, then: isKeepingAwake ? .working : .idle)
    }

    func beginDragging() {
        moodTimer?.invalidate()
        mood = .dragging
    }

    func endDragging() {
        mood = isKeepingAwake ? .working : .idle
    }

    func beginWandering() {
        guard isPetVisible, roamingEnabled, mood != .dragging else { return }
        mood = .walking
    }

    func endWandering() {
        guard mood == .walking else { return }
        mood = isKeepingAwake ? .working : .idle
    }

    func dismissBreakReminder(snoozeMinutes: Int? = nil) {
        guard isBreakDue else { return }
        isBreakDue = false
        setMood(isKeepingAwake ? .working : .idle)

        let delayMinutes = max(snoozeMinutes ?? breakIntervalMinutes, 1)
        statusMessage = snoozeMinutes == nil
            ? "Хорошая пауза · следующий мягкий сигнал через \(delayMinutes) мин"
            : "Хорошо · напомню ещё раз через \(delayMinutes) мин"
        scheduleBreakReminder(after: TimeInterval(delayMinutes * 60))
        schedulePlayfulMoment()
    }

    // MARK: Private helpers

    private func startPowerAssertions(reason: String) {
        guard !isKeepingAwake else { return }
        powerWarning = nil
        let result = powerKeeper.begin(reason: reason, keepDisplayOn: keepDisplayAwake)
        guard result.success else {
            manualAwake = false
            isKeepingAwake = false
            isFocusSession = false
            sessionTimer?.invalidate()
            sessionTimer = nil
            breakTimer?.invalidate()
            breakTimer = nil
            isBreakDue = false
            sessionEndDate = nil
            sessionCompletionAction = nil
            remainingSeconds = nil
            powerWarning = result.message
            statusMessage = result.message ?? "Не удалось включить защиту от сна"
            setTemporaryMood(.resting, duration: 1.8, then: .idle)
            return
        }

        isKeepingAwake = true
        powerWarning = result.message
        scheduleBreakReminder()
    }

    private func refreshPowerAssertions() {
        let result = powerKeeper.begin(
            reason: isFocusSession ? "Sweet No Sleep — фокус-сессия" : "Sweet No Sleep — ручной режим",
            keepDisplayOn: keepDisplayAwake
        )
        guard result.success else {
            sessionTimer?.invalidate()
            sessionTimer = nil
            breakTimer?.invalidate()
            breakTimer = nil
            isBreakDue = false
            sessionEndDate = nil
            sessionCompletionAction = nil
            remainingSeconds = nil
            isFocusSession = false
            manualAwake = false
            isKeepingAwake = false
            powerWarning = result.message
            statusMessage = result.message ?? "Защиту от сна не удалось обновить"
            setTemporaryMood(.resting, duration: 1.8, then: .idle)
            return
        }
        powerWarning = result.message
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
        let otherWorkRemains = manualAwake || !agentLeases.isEmpty
        if otherWorkRemains {
            isKeepingAwake = true
            statusMessage = activeAgentCount > 0
                ? "Таймер завершён · агент всё ещё работает"
                : "Таймер завершён · ручная защита остаётся включённой"
        } else {
            powerKeeper.end()
            breakTimer?.invalidate()
            breakTimer = nil
            isBreakDue = false
            isKeepingAwake = false
            powerWarning = nil
            statusMessage = "Цель достигнута · сессия завершена"
        }

        setTemporaryMood(.celebrating, duration: 2.2, then: .idle)

        guard shouldSleepImmediately, !otherWorkRemains else { return }
        // Let the release of our assertions reach power management first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, let error = self.powerKeeper.requestImmediateSleep() else { return }
            self.statusMessage = "Сессия завершена, но сон не запущен: \(error)"
            self.powerWarning = error
        }
    }

    private func schedulePlayfulMoment() {
        playfulTimer?.invalidate()
        playfulTimer = nil
        guard isKeepingAwake, isPetVisible, animationsEnabled, playfulMomentsEnabled, !isBreakDue else { return }

        let delay = TimeInterval.random(in: 210...390)
        playfulTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.playfulTimer = nil
            guard self.isKeepingAwake,
                  self.isPetVisible,
                  self.animationsEnabled,
                  self.playfulMomentsEnabled,
                  !self.isBreakDue,
                  self.mood != .dragging
            else {
                self.schedulePlayfulMoment()
                return
            }

            let moments: [KiwiMood] = [.dancing, .stretching, .curious]
            let moment = moments.randomElement() ?? .stretching
            let duration = TimeInterval.random(in: 3.4...5.2)
            self.setTemporaryMood(moment, duration: duration, then: .working)
            self.schedulePlayfulMoment()
        }
    }

    private func scheduleBreakReminder(after delay: TimeInterval? = nil) {
        breakTimer?.invalidate()
        breakTimer = nil
        guard breakRemindersEnabled, isKeepingAwake, !isBreakDue else { return }

        let interval = delay ?? TimeInterval(breakIntervalMinutes * 60)
        breakTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.breakTimer = nil
            guard self.isKeepingAwake, self.breakRemindersEnabled else { return }
            self.isBreakDue = true
            self.playfulTimer?.invalidate()
            self.playfulTimer = nil
            self.statusMessage = "Пора ненадолго отвести взгляд от кода"
            self.setMood(.breakReminder)
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
            guard let self else { return }
            self.mood = self.isKeepingAwake ? (finalMood == .idle ? .working : finalMood) : finalMood
        }
    }

    private enum Key {
        static let selectedMinutes = "session.selectedMinutes"
        static let skin = "pet.skin"
        static let petSize = "pet.size"
        static let keepDisplayAwake = "power.keepDisplayAwake"
        static let completionAction = "session.completionAction"
        static let resumeOnLaunch = "power.resumeOnLaunch"
        static let agentBridgeEnabled = "agentBridge.enabled"
        static let petVisible = "pet.visible"
        static let alwaysOnTop = "pet.alwaysOnTop"
        static let roamingEnabled = "pet.roamingEnabled"
        static let animationsEnabled = "pet.animationsEnabled"
        static let playfulMomentsEnabled = "pet.playfulMomentsEnabled"
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
