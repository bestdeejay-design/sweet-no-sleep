import Foundation
import IOKit.pwr_mgt
import AppKit

// Keeps the Mac awake (display + idle sleep) while the pet is on duty.
final class PowerKeeper: ObservableObject {
    // True while an assertion is currently held.
    @Published private(set) var isAwake: Bool = false

    // ProcessInfo activity handle (idle + display sleep).
    private var activity: NSObjectProtocol?
    // IOKit display-sleep assertion handle.
    private var displayID: IOPMAssertionID = 0
    // Last reason string, reused after system wake.
    private var lastReason: String = ""
    // Wake-notification observer token.
    private var wakeObserver: NSObjectProtocol?

    init() {
        // Re-assert the display assertion after sleep/wake cycles.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidWake()
        }
    }

    deinit {
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        releaseAssertion()
    }

    // Acquire both assertions. Safe to call repeatedly.
    func keepAwake(reason: String) {
        lastReason = reason
        if isAwake {
            return
        }
        let options: ProcessInfo.ActivityOptions = [.idleDisplaySleepDisabled, .idleSystemSleepDisabled]
        activity = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
        let name = kIOPMAssertionTypeNoDisplaySleep as CFString
        let cfReason = reason as CFString
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            name,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            cfReason,
            &newID
        )
        if result == kIOReturnSuccess {
            displayID = newID
        } else {
            displayID = 0
        }
        isAwake = true
    }

    // Adapter used by SweetNoSleepApp / KiwiBrain.awakeHandler.
    func setAwake(_ awake: Bool) {
        if awake {
            keepAwake(reason: lastReason.isEmpty ? "SweetNoSleep" : lastReason)
        } else {
            letSleep()
        }
    }

    // Release both assertions. Safe to call when idle.
    func letSleep() {
        lastReason = ""
        releaseAssertion()
        isAwake = false
    }

    // Re-acquire the IOKit assertion after wake if we were awake.
    private func handleDidWake() {
        guard isAwake else {
            return
        }
        if displayID != 0 {
            IOPMAssertionRelease(displayID)
            displayID = 0
        }
        let reason = lastReason.isEmpty ? "SweetNoSleep" : lastReason
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newID
        )
        if result == kIOReturnSuccess {
            displayID = newID
        }
    }

    // Release handles without touching published state (deinit safe).
    private func releaseAssertion() {
        if let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        }
        if displayID != 0 {
            IOPMAssertionRelease(displayID)
            displayID = 0
        }
    }
}
