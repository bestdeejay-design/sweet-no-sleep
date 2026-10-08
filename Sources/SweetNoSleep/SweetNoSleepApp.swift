import AppKit
import Combine
import SwiftUI

@main
struct SweetNoSleepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = SweetNoSleepModel.shared

    var body: some Scene {
        // The persona, not a hardcoded cat: a character pack such as Kot-Arbuz
        // must never be addressed as Kiwi (issue #21 audit).
        MenuBarExtra(model.characterName, systemImage: "leaf.fill") {
            MenuBarDashboard(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petController: PetPanelController?
    private var cancellables = Set<AnyCancellable>()
    private var sigtermSource: DispatchSourceSignal?
    private var sigintSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        setupTerminationSignalHandlers()

        let model = SweetNoSleepModel.shared
        let controller = PetPanelController(model: model)
        petController = controller

        model.$isPetVisible.dropFirst().sink { [weak self] isVisible in
            DispatchQueue.main.async {
                guard let self else { return }
                if isVisible {
                    self.petController?.show()
                } else {
                    self.petController?.hide()
                }
            }
        }.store(in: &cancellables)

        if model.isPetVisible {
            controller.show()
        }
        if model.resumeKeepAwakeOnLaunch {
            model.startManualAwake()
        }
    }

    private func setupTerminationSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler { [weak self] in
            SweetNoSleepModel.shared.shutdown()
            self?.petController?.close()
            exit(0)
        }
        sigterm.resume()
        sigtermSource = sigterm

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler { [weak self] in
            SweetNoSleepModel.shared.shutdown()
            self?.petController?.close()
            exit(0)
        }
        sigint.resume()
        sigintSource = sigint
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            SweetNoSleepModel.shared.handleAgentURL(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if SweetNoSleepModel.shared.isPetVisible {
            petController?.show()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        SweetNoSleepModel.shared.shutdown()
        petController?.close()
        petController = nil
        sigtermSource?.cancel()
        sigtermSource = nil
        sigintSource?.cancel()
        sigintSource = nil
    }
}

// MARK: - Menu bar dashboard

private struct MenuBarDashboard: View {
    @ObservedObject var model: SweetNoSleepModel
    @Environment(\.openSettings) private var openSettings
    @State private var confirmsImmediateSleep = false
    @State private var showDiagnostics = false

    private let durations = [25, 50, 90, 120]

    /// Extra height for the per-session rows in the agents card. Only counted
    /// while that card is actually on screen: during a focus session the
    /// running-session card replaces it, so the rows would add empty space
    /// (issue #21 audit). Longer lists and wrapped reasons scroll (issue #19).
    private var agentRowsHeight: CGFloat {
        guard model.activeAgentCount > 0, !model.isFocusSession else { return 0 }
        return 24 + CGFloat(min(model.activeAgentCount, 4)) * 18
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 22)

            // The middle cards scroll when they outgrow the panel (long agent
            // questions, several sessions, expanded diagnostics), so the footer
            // with Settings / Quit can never be pushed off the bottom edge.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    companionCard
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    powerCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    if model.isFocusSession {
                        runningSessionCard
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    } else if model.activeAgentCount > 0 {
                        agentSessionCard
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    } else {
                        focusCard
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }

                    diagnosticsCard
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }
            }

            Spacer(minLength: 12)
            footer
                .padding(.horizontal, 19)
                .padding(.bottom, 17)
        }
        .frame(width: 362, height: (model.isFocusSession ? 660 : 640) + agentRowsHeight + (showDiagnostics ? 110 : 0))
        .animation(.easeInOut(duration: 0.18), value: showDiagnostics)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color(hex: 0x111A2B), Color(hex: 0x0B101B)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color(hex: 0x6CCB83, opacity: 0.10))
                    .frame(width: 190, height: 190)
                    .blur(radius: 58)
                    .offset(x: 70, y: -78)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            L10n.text("After this session, your Mac will go to sleep immediately"),
            isPresented: $confirmsImmediateSleep,
            titleVisibility: .visible
        ) {
            Button(L10n.text("I understand - start session"), role: .destructive) {
                model.startFocusSession(confirmedImmediateSleep: true)
            }
            Button(L10n.text("Cancel"), role: .cancel) { }
        } message: {
            Text(L10n.text("Open apps and agents may be interrupted. To use the normal idle-sleep behavior, choose 'Allow normal sleep' in Settings."))
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("SWEET NO SLEEP"))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2.1)
                    .foregroundStyle(Color(hex: 0xA9D8B0))
                Text(L10n.text("KIWI CAT - your work companion"))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isKeepingAwake ? Color(hex: 0x7BDB91) : Color(hex: 0x718096))
                    .frame(width: 7, height: 7)
                Text(model.isKeepingAwake ? L10n.text("ON DUTY") : L10n.text("RESTING"))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.07), in: Capsule())
        }
    }

    private var companionCard: some View {
        HStack(spacing: 15) {
            KiwiPetView(model: model, sizeOverride: 104, allowsDragging: false, tracksCursor: false)
                .frame(width: 116, height: 116)
                .background(
                    RadialGradient(
                        colors: [Color(hex: 0x7FCF83, opacity: 0.14), .clear],
                        center: .center,
                        startRadius: 5,
                        endRadius: 70
                    )
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(model.hasWaitingAgent
                    ? L10n.format("%@ needs your approval", model.characterName)
                    : (model.activeAgentCount > 0 ? L10n.format("%@ is with your agent", model.characterName) : (model.isKeepingAwake ? L10n.format("%@ is on duty", model.characterName) : L10n.format("%@ is ready to help", model.characterName))))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.statusMessage)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = model.powerWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: 0xFFD28A))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Color(hex: 0x182337, opacity: 0.84), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var powerCard: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: model.isKeepingAwake ? 0x285039 : 0x263044))
                    .frame(width: 40, height: 40)
                Image(systemName: model.isKeepingAwake ? "bolt.fill" : "moon.zzz.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.isKeepingAwake ? Color(hex: 0x99E2A3) : Color(hex: 0xB6C2D5))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("Keep Mac awake"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(model.isKeepingAwake ? L10n.text("System idle sleep is prevented") : L10n.text("Turn on manually with no timer"))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 4)
            Toggle(L10n.text("Keep Mac awake"), isOn: Binding(
                get: { model.isKeepingAwake },
                set: { model.setKeepAwake($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Color(hex: 0x7BCB86))
            .accessibilityLabel(L10n.text("Keep Mac awake"))
        }
        .padding(14)
        .background(Color(hex: 0x151F30, opacity: 0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(L10n.text("FOCUS SESSION"), systemImage: "sparkles")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Color(hex: 0xA9D8B0))
                Spacer()
                Text(model.completionAction == .sleepImmediately ? L10n.text("SLEEP WHEN DONE") : L10n.text("TIMED SESSION"))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.48))
            }

            HStack(spacing: 7) {
                ForEach(durations, id: \.self) { minutes in
                    Button {
                        model.selectedMinutes = minutes
                    } label: {
                        Text(L10n.format("%d min", minutes))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(model.selectedMinutes == minutes ? Color(hex: 0x101B18) : .white.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                Capsule()
                                    .fill(model.selectedMinutes == minutes ? Color(hex: 0x9BDEA2) : .white.opacity(0.07))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.format("A %d-minute session", minutes))
                }
            }

            Button(action: beginFocusSession) {
                HStack(spacing: 9) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(L10n.text("Start focus"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Spacer()
                    Text(L10n.format("%d min", model.selectedMinutes))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .opacity(0.76)
                }
                .foregroundStyle(Color(hex: 0x122018))
                .padding(.horizontal, 15)
                .frame(height: 42)
                .background(
                    LinearGradient(colors: [Color(hex: 0xA7E4A9), Color(hex: 0x78C889)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(15)
        .background(Color(hex: 0x151F30, opacity: 0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var agentSessionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                model.hasWaitingAgent ? L10n.text("AGENT NEEDS APPROVAL") : L10n.text("AGENTS AT WORK"),
                systemImage: model.hasWaitingAgent ? "questionmark.circle.fill" : "cpu"
            )
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.0)
            .foregroundStyle(model.hasWaitingAgent ? AgentIndicator.waitingColor : Color(hex: 0xA9D8B0))
            Text(L10n.format("%d active agents", model.activeAgentCount))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if let reason = model.agentWaitingReason {
                Text(L10n.format("Agent question: %@", reason))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AgentIndicator.waitingColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TimelineView(.periodic(from: .now, by: 5)) { timeline in
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(model.agentSessionSummaries) { session in
                        agentRow(session, now: timeline.date)
                    }
                }
            }
            Text(L10n.format("Protection remains active while heartbeats arrive. After 3 minutes without a signal, %@ releases the assertion so the Mac is not kept awake indefinitely.", model.characterName))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.endAgentSessions()
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text(L10n.text("End agent sessions"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(15)
        .background(Color(hex: 0x151F30, opacity: 0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0x82D28E, opacity: 0.22), lineWidth: 1)
        }
    }

    private func agentRow(_ session: AgentSessionSummary, now: Date) -> some View {
        let minutes = max(1, Int(now.timeIntervalSince(session.startedAt) / 60))
        let age = minutes < 60
            ? L10n.format("%d min", minutes)
            : L10n.format("%d h %d min", minutes / 60, minutes % 60)
        return HStack(spacing: 8) {
            Circle()
                .fill(session.isWaiting ? AgentIndicator.waitingColor : Color(hex: 0x7ED18A))
                .frame(width: 7, height: 7)
            Text(session.shortID)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
            Text(session.isWaiting ? L10n.text("Waiting for your answer") : L10n.text("Working"))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(session.isWaiting ? AgentIndicator.waitingColor : .white.opacity(0.60))
            Spacer(minLength: 6)
            Text(age)
                .font(.system(size: 9, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var runningSessionCard: some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Label(L10n.text("FOCUS IN PROGRESS"), systemImage: "timer")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(Color(hex: 0xA9D8B0))
                Spacer()
                Text(L10n.text("Mac is protected from idle sleep"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.50))
            }
            Text((TimeInterval(model.remainingSeconds ?? 0)).shortCountdown)
                .font(.system(size: 38, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.activeAgentCount > 0 {
                Text(L10n.format("Agent connections: %d", model.activeAgentCount))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Color(hex: 0xA9D8B0))
            }
            Button {
                model.stopKeepingAwake()
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text(L10n.text("End session"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(15)
        .background(Color(hex: 0x151F30, opacity: 0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0x82D28E, opacity: 0.22), lineWidth: 1)
        }
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showDiagnostics.toggle()
                }
            } label: {
                HStack {
                    Label(L10n.text("Hold diagnostics"), systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(Color(hex: 0xA9D8B0))
                    Spacer()
                    Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.50))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDiagnostics {
                VStack(alignment: .leading, spacing: 5) {
                    diagnosticDashboardRow(
                        label: L10n.text("System assertion"),
                        value: model.diagnostics.isSystemActive
                            ? L10n.format("Active (ID: %u)", model.diagnostics.systemAssertionID)
                            : L10n.text("Inactive")
                    )
                    diagnosticDashboardRow(
                        label: L10n.text("Display assertion"),
                        value: model.diagnostics.isDisplayActive
                            ? L10n.format("Active (ID: %u)", model.diagnostics.displayAssertionID)
                            : L10n.text("Inactive")
                    )
                    if model.diagnostics.isSystemActive || model.diagnostics.isDisplayActive {
                        diagnosticDashboardRow(
                            label: L10n.text("Next re-arm"),
                            value: L10n.format("%d s", model.diagnostics.secondsUntilRearm)
                        )
                    }
                    diagnosticDashboardRow(
                        label: L10n.text("Power source"),
                        value: model.diagnostics.batteryDescription
                    )
                    diagnosticDashboardRow(
                        label: L10n.text("Last power event"),
                        value: model.diagnostics.lastPowerEvent
                    )
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color(hex: 0x151F30, opacity: 0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func diagnosticDashboardRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10, weight: .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.trailing)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                model.isPetVisible.toggle()
            } label: {
                Label(model.isPetVisible ? L10n.format("Hide %@", model.characterName) : L10n.format("Show %@", model.characterName), systemImage: model.isPetVisible ? "eye.slash" : "eye")
            }
            .help(model.isPetVisible ? L10n.text("Hide the pet from the desktop") : L10n.text("Show the pet on the desktop"))

            Spacer(minLength: 6)
            Button {
                presentSettings()
            } label: {
                Label(L10n.text("Settings"), systemImage: "slider.horizontal.3")
            }
            .help(L10n.text("Configure the timer, skin, pet size, animations, breaks, agent hooks, and power settings."))
            Spacer(minLength: 6)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .accessibilityLabel(L10n.text("Quit"))
            }
            .help(L10n.text("Quit Sweet No Sleep"))
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.67))
        .buttonStyle(.plain)
    }

    private func presentSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let settingsAction = openSettings
        Task { @MainActor [settingsAction] in
            await Task.yield()
            NSApplication.shared.activate(ignoringOtherApps: true)
            settingsAction()
        }
    }

    private func beginFocusSession() {
        if model.completionAction == .sleepImmediately {
            confirmsImmediateSleep = true
        } else {
            model.startFocusSession()
        }
    }
}
