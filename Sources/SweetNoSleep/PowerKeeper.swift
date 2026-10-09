import AppKit
import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

/// Owns the temporary macOS power assertions used by focus sessions.
///
/// Assertions are created with an automatic 120-second timeout (P0) so that
/// any crash or force-kill cleanly expires in the kernel without keeping the
/// Mac awake indefinitely. While active, assertions are re-armed at 75% of
/// the lifetime (~90 s in).
@MainActor
final class PowerKeeper {
    private var activity: NSObjectProtocol?
    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var wakeObserver: NSObjectProtocol?
    private var willSleepObserver: NSObjectProtocol?
    private var rearmTimer: Timer?
    private var reason = "Sweet No Sleep - focus session"
    private var humanReadableReason = "Sweet No Sleep - focus session"
    private var shouldKeepDisplayOn = false

    private static let assertionTimeoutSeconds: Int = 120
    private static let rearmIntervalSeconds: TimeInterval = 90

    private(set) var isActive = false
    private(set) var nextRearmDate: Date?
    private(set) var lastPowerEvent: String = L10n.text("None")

    var systemAssertionID: IOPMAssertionID { systemAssertion }
    var displayAssertionID: IOPMAssertionID { displayAssertion }
    var isSystemAsserted: Bool { systemAssertion != 0 }
    var isDisplayAsserted: Bool { displayAssertion != 0 }

    var onFailure: ((String) -> Void)?
    var onWarning: ((String) -> Void)?
    var onDiagnosticsChanged: (() -> Void)?

    init() {
        let center = NSWorkspace.shared.notificationCenter
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reassertAfterWake()
            }
        }
        willSleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWillSleep()
            }
        }
    }

    /// Starts an idle-system-sleep assertion and, optionally, a display assertion.
    /// Returns a user-readable error if macOS rejects the system assertion; a
    /// display-only failure is returned as a non-fatal warning.
    func begin(
        reason: String,
        humanReadableReason: String,
        keepDisplayOn: Bool
    ) -> (success: Bool, message: String?) {
        self.reason = reason
        self.humanReadableReason = humanReadableReason
        shouldKeepDisplayOn = keepDisplayOn

        if isActive, systemAssertion != 0 {
            // Repeated requests coalesce into the existing system assertion.
            // Update assertion properties without recreating the ID.
            updateAssertionProperties(
                id: systemAssertion,
                name: reason,
                humanReadableReason: humanReadableReason
            )
            if displayAssertion != 0 {
                updateAssertionProperties(
                    id: displayAssertion,
                    name: "\(reason) - display",
                    humanReadableReason: L10n.format("%@ (display)", humanReadableReason)
                )
            }
            onDiagnosticsChanged?()
            return (true, updateDisplayAssertion(keepDisplayOn: keepDisplayOn))
        }

        end()
        self.reason = reason
        self.humanReadableReason = humanReadableReason
        self.shouldKeepDisplayOn = keepDisplayOn

        // Keep the app out of App Nap without asking ProcessInfo to create a
        // second PreventUserIdleSystemSleep assertion. IOKit owns that assertion.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: reason
        )

        let systemResult = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            name: reason,
            humanReadableReason: humanReadableReason,
            id: &systemAssertion
        )

        guard systemResult == kIOReturnSuccess else {
            releaseAssertionIDs()
            if let activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
            lastPowerEvent = L10n.text("Assertions released")
            onDiagnosticsChanged?()
            return (false, L10n.format("macOS could not prevent system sleep (error %d).", systemResult))
        }

        isActive = true
        startRearmTimer()
        lastPowerEvent = L10n.text("Assertions active (120s timeout)")
        onDiagnosticsChanged?()
        return (true, updateDisplayAssertion(keepDisplayOn: keepDisplayOn))
    }

    /// Releases every assertion. Safe to call more than once.
    func end() {
        stopRearmTimer()
        nextRearmDate = nil
        releaseAssertionIDs()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        isActive = false
        lastPowerEvent = L10n.text("Assertions released")
        onDiagnosticsChanged?()
    }

    /// Performs explicit app-lifecycle cleanup instead of relying on a deinit
    /// that cannot safely access this main-actor-owned state.
    func shutdown() {
        end()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let willSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(willSleepObserver)
            self.willSleepObserver = nil
        }
    }

    /// Pauses assertions temporarily (e.g. for battery floor or sleep).
    func pauseAssertions(eventDescription: String) {
        stopRearmTimer()
        nextRearmDate = nil
        releaseAssertionIDs()
        lastPowerEvent = eventDescription
        onDiagnosticsChanged?()
    }

    /// Resumes assertions after pause (e.g. power plugged back in).
    func resumeAssertions(
        keepDisplayOn: Bool,
        eventDescription: String
    ) -> (success: Bool, message: String?) {
        guard isActive else { return (false, nil) }
        shouldKeepDisplayOn = keepDisplayOn
        releaseAssertionIDs()

        let systemResult = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            name: reason,
            humanReadableReason: humanReadableReason,
            id: &systemAssertion
        )
        guard systemResult == kIOReturnSuccess else {
            releaseAssertionIDs()
            lastPowerEvent = L10n.text("Assertions released")
            onDiagnosticsChanged?()
            return (false, L10n.format("macOS could not prevent system sleep (error %d).", systemResult))
        }

        var warningMessage: String?
        if keepDisplayOn {
            let displayResult = createAssertion(
                type: kIOPMAssertionTypeNoDisplaySleep as CFString,
                name: "\(reason) - display",
                humanReadableReason: L10n.format("%@ (display)", humanReadableReason),
                id: &displayAssertion
            )
            if displayResult != kIOReturnSuccess {
                warningMessage = L10n.format("macOS could not keep the display awake (error %d); the system is still protected from idle sleep.", displayResult)
            }
        }

        startRearmTimer()
        lastPowerEvent = eventDescription
        onDiagnosticsChanged?()
        return (true, warningMessage)
    }

    func setLastPowerEvent(_ event: String) {
        lastPowerEvent = event
        onDiagnosticsChanged?()
    }

    private func updateDisplayAssertion(keepDisplayOn: Bool) -> String? {
        shouldKeepDisplayOn = keepDisplayOn

        guard keepDisplayOn else {
            if displayAssertion != 0 {
                let handle = displayAssertion
                displayAssertion = 0
                _ = IOPMAssertionRelease(handle)
                onDiagnosticsChanged?()
            }
            return nil
        }

        guard displayAssertion == 0 else { return nil }
        let displayResult = createAssertion(
            type: kIOPMAssertionTypeNoDisplaySleep as CFString,
            name: "\(reason) - display",
            humanReadableReason: L10n.format("%@ (display)", humanReadableReason),
            id: &displayAssertion
        )
        guard displayResult == kIOReturnSuccess else {
            if displayAssertion != 0 {
                let handle = displayAssertion
                displayAssertion = 0
                _ = IOPMAssertionRelease(handle)
            }
            onDiagnosticsChanged?()
            return L10n.format("macOS could not keep the display awake (error %d); the system is still protected from idle sleep.", displayResult)
        }
        onDiagnosticsChanged?()
        return nil
    }

    /// Requests immediate system sleep. This is only called after the user has
    /// explicitly selected that end-of-session action and confirmed the session.
    func requestImmediateSleep() -> String? {
        let connection = IOPMFindPowerManagement(kIOMainPortDefault)
        guard connection != IO_OBJECT_NULL else {
            return L10n.text("Could not connect to the macOS power management service.")
        }
        defer { IOServiceClose(connection) }

        let result = IOPMSleepSystem(connection)
        guard result == kIOReturnSuccess else {
            return L10n.format("macOS rejected the sleep request (error %d).", result)
        }
        return nil
    }

    private func handleWillSleep() {
        guard isActive else { return }
        stopRearmTimer()
        nextRearmDate = nil
        releaseAssertionIDs()
        lastPowerEvent = L10n.text("System will sleep: assertions released")
        onDiagnosticsChanged?()
    }

    private func reassertAfterWake() {
        guard isActive else { return }

        // Sleep/wake can invalidate IOKit assertion IDs. Keep the user-facing
        // state, but replace the old IDs with fresh assertions after wake.
        releaseAssertionIDs()
        let systemResult = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            name: reason,
            humanReadableReason: humanReadableReason,
            id: &systemAssertion
        )
        guard systemResult == kIOReturnSuccess else {
            let message = L10n.format("Could not restore idle-sleep protection after wake (error %d).", systemResult)
            end()
            onFailure?(message)
            return
        }

        if shouldKeepDisplayOn {
            let displayResult = createAssertion(
                type: kIOPMAssertionTypeNoDisplaySleep as CFString,
                name: "\(reason) - display",
                humanReadableReason: L10n.format("%@ (display)", humanReadableReason),
                id: &displayAssertion
            )
            if displayResult != kIOReturnSuccess {
                onWarning?(L10n.format("Could not keep the display awake after wake (error %d); the Mac is still protected from system sleep.", displayResult))
            }
        }

        startRearmTimer()
        lastPowerEvent = L10n.text("System woke: assertions restored")
        onDiagnosticsChanged?()
    }

    private func startRearmTimer() {
        stopRearmTimer()
        nextRearmDate = Date().addingTimeInterval(Self.rearmIntervalSeconds)
        rearmTimer = Timer.scheduledTimer(withTimeInterval: Self.rearmIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rearmAssertions()
            }
        }
    }

    private func stopRearmTimer() {
        rearmTimer?.invalidate()
        rearmTimer = nil
    }

    private func rearmAssertions() {
        guard isActive else { return }

        var rearmedAny = false

        if systemAssertion != 0 {
            let result = IOPMAssertionSetProperty(
                systemAssertion,
                kIOPMAssertionTimeoutKey as CFString,
                NSNumber(value: Self.assertionTimeoutSeconds)
            )
            if result == kIOReturnSuccess {
                rearmedAny = true
            } else {
                // If re-arm fails (kernel reaped ID), treat as dead and recreate.
                systemAssertion = 0
                let createRes = createAssertion(
                    type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    name: reason,
                    humanReadableReason: humanReadableReason,
                    id: &systemAssertion
                )
                if createRes == kIOReturnSuccess {
                    rearmedAny = true
                } else {
                    onFailure?(L10n.format("Could not restore system sleep protection during re-arm (error %d).", createRes))
                }
            }
        }

        if displayAssertion != 0 {
            let result = IOPMAssertionSetProperty(
                displayAssertion,
                kIOPMAssertionTimeoutKey as CFString,
                NSNumber(value: Self.assertionTimeoutSeconds)
            )
            if result == kIOReturnSuccess {
                rearmedAny = true
            } else {
                displayAssertion = 0
                let createRes = createAssertion(
                    type: kIOPMAssertionTypeNoDisplaySleep as CFString,
                    name: "\(reason) - display",
                    humanReadableReason: L10n.format("%@ (display)", humanReadableReason),
                    id: &displayAssertion
                )
                if createRes != kIOReturnSuccess {
                    onWarning?(L10n.format("Could not restore display sleep protection during re-arm (error %d).", createRes))
                }
            }
        }

        if rearmedAny {
            nextRearmDate = Date().addingTimeInterval(Self.rearmIntervalSeconds)
            lastPowerEvent = L10n.text("Assertions re-armed")
            onDiagnosticsChanged?()
        }
    }

    private func createAssertion(
        type: CFString,
        name: String,
        humanReadableReason: String,
        id: inout IOPMAssertionID
    ) -> IOReturn {
        let bundlePath = Bundle.main.bundlePath
        let properties: [String: Any] = [
            kIOPMAssertionTypeKey as String: type as String,
            kIOPMAssertionNameKey as String: name,
            kIOPMAssertionLevelKey as String: kIOPMAssertionLevelOn,
            kIOPMAssertionTimeoutKey as String: Self.assertionTimeoutSeconds,
            kIOPMAssertionTimeoutActionKey as String: kIOPMAssertionTimeoutActionRelease as String,
            kIOPMAssertionHumanReadableReasonKey as String: humanReadableReason,
            kIOPMAssertionLocalizationBundlePathKey as String: bundlePath
        ]
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &newID)
        if result == kIOReturnSuccess {
            id = newID
        }
        return result
    }

    private func updateAssertionProperties(
        id: IOPMAssertionID,
        name: String,
        humanReadableReason: String
    ) {
        _ = IOPMAssertionSetProperty(id, kIOPMAssertionNameKey as CFString, name as CFString)
        _ = IOPMAssertionSetProperty(id, kIOPMAssertionHumanReadableReasonKey as CFString, humanReadableReason as CFString)
    }

    private func releaseAssertionIDs() {
        if displayAssertion != 0 {
            let handle = displayAssertion
            displayAssertion = 0
            _ = IOPMAssertionRelease(handle)
        }
        if systemAssertion != 0 {
            let handle = systemAssertion
            systemAssertion = 0
            _ = IOPMAssertionRelease(handle)
        }
    }
}

// MARK: - Power source monitoring & Diagnostics models

struct PowerSourceStatus: Equatable, Sendable {
    var hasInternalBattery: Bool = false
    var isPluggedIn: Bool = true
    var isCharging: Bool = false
    var batteryPercent: Int = 100

    var descriptionText: String {
        guard hasInternalBattery else {
            return L10n.text("AC Power (No battery)")
        }
        if isCharging {
            return L10n.format("%d%% (Charging)", batteryPercent)
        } else if isPluggedIn {
            return L10n.format("%d%% (Power Adapter)", batteryPercent)
        } else {
            return L10n.format("%d%% (On battery)", batteryPercent)
        }
    }
}

struct PowerDiagnostics: Equatable, Sendable {
    var systemAssertionID: IOPMAssertionID = 0
    var displayAssertionID: IOPMAssertionID = 0
    var isSystemActive: Bool = false
    var isDisplayActive: Bool = false
    var secondsUntilRearm: Int = 0
    var batteryDescription: String = "AC Power (No battery)"
    var lastPowerEvent: String = "None"
    /// Active keep-awake sources (manual / focus / agent). Shown in diagnostics
    /// because pmset only prints the assertion name of the first class that won.
    var awakeSources: String = "none"
}

@MainActor
final class PowerSourceMonitor {
    private var timerSource: DispatchSourceTimer?
    private(set) var currentStatus: PowerSourceStatus = PowerSourceStatus()
    var onStatusChange: ((PowerSourceStatus) -> Void)?

    init() {
        currentStatus = Self.readCurrentStatus()
        startPolling()
    }

    func startPolling() {
        let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer.schedule(deadline: .now() + 20, repeating: .seconds(20), leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        timerSource = timer
    }

    func poll() {
        let status = Self.readCurrentStatus()
        if status != currentStatus {
            currentStatus = status
            onStatusChange?(status)
        }
    }

    func shutdown() {
        timerSource?.cancel()
        timerSource = nil
    }

    static func readCurrentStatus() -> PowerSourceStatus {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSourceStatus(hasInternalBattery: false, isPluggedIn: true, isCharging: false, batteryPercent: 100)
        }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef], !sources.isEmpty else {
            return PowerSourceStatus(hasInternalBattery: false, isPluggedIn: true, isCharging: false, batteryPercent: 100)
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = description[kIOPSTypeKey as String] as? String
            if type == (kIOPSInternalBatteryType as String) {
                let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int ?? 0
                let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int ?? 100
                let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
                let powerState = description[kIOPSPowerSourceStateKey as String] as? String
                let isPluggedIn = (powerState == (kIOPSACPowerValue as String))
                let percent = maxCapacity > 0 ? Int((Double(currentCapacity) / Double(maxCapacity)) * 100) : currentCapacity
                return PowerSourceStatus(
                    hasInternalBattery: true,
                    isPluggedIn: isPluggedIn,
                    isCharging: isCharging,
                    batteryPercent: min(max(percent, 0), 100)
                )
            }
        }
        return PowerSourceStatus(hasInternalBattery: false, isPluggedIn: true, isCharging: false, batteryPercent: 100)
    }
}
