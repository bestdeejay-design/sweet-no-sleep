import AppKit
import Foundation
import IOKit
import IOKit.pwr_mgt

/// Owns the temporary macOS power assertions used by focus sessions.
///
/// The app takes an assertion only after an explicit user action and releases it
/// as soon as the session ends. System sleep prevention and display sleep
/// prevention are deliberately separate: the display is allowed to turn off by
/// default, which saves battery while keeping long-running work alive.
@MainActor
final class PowerKeeper {
    private var activity: NSObjectProtocol?
    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var wakeObserver: NSObjectProtocol?
    private var reason = "Sweet No Sleep - focus session"
    private var shouldKeepDisplayOn = false
    var onFailure: ((String) -> Void)?
    var onWarning: ((String) -> Void)?

    private(set) var isActive = false

    init() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reassertAfterWake()
            }
        }
    }

    /// Starts an idle-system-sleep assertion and, optionally, a display assertion.
    /// Returns a user-readable error if macOS rejects the system assertion; a
    /// display-only failure is returned as a non-fatal warning.
    func begin(reason: String, keepDisplayOn: Bool) -> (success: Bool, message: String?) {
        if isActive, systemAssertion != 0 {
            // Repeated requests coalesce into the existing system assertion.
            // Only reconcile the optional display assertion on a settings change.
            self.reason = reason
            return (true, updateDisplayAssertion(keepDisplayOn: keepDisplayOn))
        }

        end()
        self.reason = reason

        // Keep the app out of App Nap without asking ProcessInfo to create a
        // second PreventUserIdleSystemSleep assertion. IOKit owns that assertion.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: reason
        )

        let systemResult = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            name: reason,
            id: &systemAssertion
        )

        guard systemResult == kIOReturnSuccess else {
            releaseAssertionIDs()
            if let activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
            return (false, L10n.format("macOS could not prevent system sleep (error %d).", systemResult))
        }

        isActive = true
        return (true, updateDisplayAssertion(keepDisplayOn: keepDisplayOn))
    }

    /// Releases every assertion. Safe to call more than once.
    func end() {
        releaseAssertionIDs()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        isActive = false
    }

    /// Performs explicit app-lifecycle cleanup instead of relying on a deinit
    /// that cannot safely access this main-actor-owned state.
    func shutdown() {
        end()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func updateDisplayAssertion(keepDisplayOn: Bool) -> String? {
        shouldKeepDisplayOn = keepDisplayOn

        guard keepDisplayOn else {
            if displayAssertion != 0 {
                IOPMAssertionRelease(displayAssertion)
                displayAssertion = 0
            }
            return nil
        }

        guard displayAssertion == 0 else { return nil }
        let displayResult = createAssertion(
            type: kIOPMAssertionTypeNoDisplaySleep as CFString,
            name: "\(reason) - display",
            id: &displayAssertion
        )
        guard displayResult == kIOReturnSuccess else {
            if displayAssertion != 0 {
                IOPMAssertionRelease(displayAssertion)
                displayAssertion = 0
            }
            return L10n.format("macOS could not keep the display awake (error %d); the system is still protected from idle sleep.", displayResult)
        }
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

    private func reassertAfterWake() {
        guard isActive else { return }

        // Sleep/wake can invalidate IOKit assertion IDs. Keep the user-facing
        // state, but replace the old IDs with fresh assertions after wake.
        releaseAssertionIDs()
        let systemResult = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            name: reason,
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
                id: &displayAssertion
            )
            if displayResult != kIOReturnSuccess {
                onWarning?(L10n.format("Could not keep the display awake after wake (error %d); the Mac is still protected from system sleep.", displayResult))
            }
        }
    }

    private func createAssertion(
        type: CFString,
        name: String,
        id: inout IOPMAssertionID
    ) -> IOReturn {
        IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
    }

    private func releaseAssertionIDs() {
        if displayAssertion != 0 {
            IOPMAssertionRelease(displayAssertion)
            displayAssertion = 0
        }
        if systemAssertion != 0 {
            IOPMAssertionRelease(systemAssertion)
            systemAssertion = 0
        }
    }
}
