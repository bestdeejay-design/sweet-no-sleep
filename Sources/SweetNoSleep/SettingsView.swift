import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SweetNoSleepModel

    var body: some View {
        TabView {
            FocusSettingsPane(model: model)
                .tabItem { Label(L10n.text("Focus"), systemImage: "bolt.fill") }
            CompanionSettingsPane(model: model)
                .tabItem { Label(L10n.text("Pet"), systemImage: "pawprint.fill") }
            PowerSettingsPane(model: model)
                .tabItem { Label(L10n.text("Power"), systemImage: "battery.100percent") }
        }
        .frame(width: 660, height: 535)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Focus

private struct FocusSettingsPane: View {
    @ObservedObject var model: SweetNoSleepModel

    private var durationBinding: Binding<Double> {
        Binding(
            get: { Double(model.selectedMinutes) },
            set: { model.selectedMinutes = Int($0) }
        )
    }

    var body: some View {
        SettingsScrollPane {
            SettingsHero(
                symbol: "bolt.fill",
                title: L10n.text("Focus without unexpected sleep"),
                subtitle: L10n.text("Start a session manually and choose what Kiwi should do when it ends.")
            )

            SettingsCard(title: L10n.text("Duration"), subtitle: L10n.format("Selected: %d minutes", model.selectedMinutes)) {
                Slider(value: durationBinding, in: 15...240, step: 5)
                    .tint(Color(hex: 0x74C987))
                    .accessibilityLabel(L10n.text("Session duration in minutes"))
                HStack {
                    Text(L10n.text("15 min"))
                    Spacer()
                    Text(L10n.text("4 hours"))
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
            }

            SettingsCard(title: L10n.text("When the goal is reached"), subtitle: L10n.text("We recommend the safer option: let macOS follow its normal sleep settings.")) {
                Picker(L10n.text("After-session action"), selection: $model.completionAction) {
                    ForEach(SessionCompletionAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.completionAction == .sleepImmediately {
                    Label(
                        L10n.text("You will be asked to confirm each session. Immediate sleep can interrupt other apps and agents."),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0xD99142))
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(SessionCompletionAction.allowNormalSleep.detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard(title: L10n.text("Quick switch"), subtitle: L10n.text("This switch shows the actual state and ends any current session.")) {
                Toggle(isOn: Binding(
                    get: { model.isKeepingAwake },
                    set: { model.setKeepAwake($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("Keep Mac awake"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(L10n.text("Keep the system awake until you turn this off"))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }
}

// MARK: - Pet

private struct CompanionSettingsPane: View {
    @ObservedObject var model: SweetNoSleepModel

    private var sizeBinding: Binding<Double> {
        Binding(get: { model.petSize }, set: { model.petSize = $0 })
    }

    var body: some View {
        SettingsScrollPane {
            SettingsHero(
                symbol: "pawprint.fill",
                title: L10n.text("Kiwi's personality"),
                subtitle: L10n.text("Choose Kiwi's look and how visibly the pet joins your workday.")
            )

            SettingsCard(title: L10n.text("Skin library"), subtitle: L10n.text("Choose a look. New skins install separately and do not require source-code changes.")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                    ForEach(model.availableSkins) { skin in
                        skinChoice(skin)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        guard let directory = PetSkinLibrary.userDirectory else { return }
                        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    } label: {
                        Label(L10n.text("Open skins folder"), systemImage: "folder")
                    }
                    .buttonStyle(.link)

                    Button {
                        model.reloadSkinLibrary()
                    } label: {
                        Label(L10n.text("Refresh list"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.link)
                }

                Text(L10n.text("User folder: ~/Library/Application Support/SweetNoSleep/PetSkins - place one skin.json in each skin folder."))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: L10n.text("Pet size"), subtitle: L10n.format("Current size: %d pt - changes apply immediately on the desktop.", Int(model.petSize))) {
                Slider(value: sizeBinding, in: 90...170, step: 2)
                    .tint(Color(hex: 0x74C987))
                    .accessibilityLabel(L10n.text("Pet size"))
                HStack {
                    Text(L10n.text("90 pt - compact"))
                    Spacer()
                    Text(L10n.text("170 pt - large"))
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                Label(L10n.text("Drag the pet to place it wherever it feels comfortable."), systemImage: "hand.draw")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: L10n.text("Behavior"), subtitle: L10n.text("Playful moments happen only during an awake session; everything can be turned off.")) {
                Toggle(L10n.text("Roam gently across the screen"), isOn: $model.roamingEnabled)
                Label(L10n.text("The first stroll starts about 3 seconds after enabling; later strolls begin about every 28 seconds."), systemImage: "figure.walk")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                Toggle(L10n.text("Keep above other windows"), isOn: $model.alwaysOnTop)
                Toggle(L10n.text("Breathing, blinking, and movement"), isOn: $model.animationsEnabled)
                Toggle(L10n.text("Occasional dances, stretches, and curious looks"), isOn: $model.playfulMomentsEnabled)
                    .disabled(!model.animationsEnabled)
                Label(L10n.text("Kiwi's eyes follow the pointer automatically."), systemImage: "eye")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: L10n.text("Eye and attention breaks"), subtitle: L10n.text("During an awake session, Kiwi gently suggests looking away from code and into the distance for about 20 seconds.")) {
                Toggle(L10n.text("Remind me to take a short break"), isOn: $model.breakRemindersEnabled)
                if model.breakRemindersEnabled {
                    HStack(spacing: 10) {
                        Text(L10n.format("Every %d min", model.breakIntervalMinutes))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .frame(width: 112, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(model.breakIntervalMinutes) },
                            set: { model.breakIntervalMinutes = Int($0) }
                        ), in: 10...60, step: 5)
                        .tint(Color(hex: 0x74C987))
                        .accessibilityLabel(L10n.text("Interval between break reminders"))
                    }
                    if model.isBreakDue {
                        Label(L10n.text("Your break reminder is ready. It is a suggestion, not a work blocker."), systemImage: "eye")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Color(hex: 0x5EAC70))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsCard(title: L10n.text("Desktop layer"), subtitle: L10n.text("The pet window is transparent and does not take focus away from your code editor.")) {
                Toggle(L10n.text("Show Kiwi on the desktop"), isOn: $model.isPetVisible)
            }
        }
    }

    private func skinChoice(_ skin: PetSkinDefinition) -> some View {
        let palette = PetPalette.palette(for: skin)
        let isSelected = model.selectedSkinID == skin.id
        return Button {
            model.selectedSkinID = skin.id
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 5) {
                    Circle().fill(palette.fur).frame(width: 15, height: 15)
                    Circle().fill(palette.accent).frame(width: 15, height: 15)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x5BAF70))
                    }
                }
                Text(skin.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(skin.subtitle)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? Color(hex: 0x72C183) : Color.primary.opacity(0.09), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format("Skin: %@", skin.name))
        .accessibilityAddTraits(isSelected ? .isSelected : .isButton)
    }
}

// MARK: - Power and startup

private struct PowerSettingsPane: View {
    @ObservedObject var model: SweetNoSleepModel
    @State private var launchAtLogin = false
    @State private var loginMessage: String?
    @State private var loginNeedsApproval = false

    var body: some View {
        SettingsScrollPane {
            SettingsHero(
                symbol: "battery.100percent",
                title: L10n.text("Power and startup"),
                subtitle: L10n.text("Sleep protection is active only while awake mode or a timer is running.")
            )

            SettingsCard(title: L10n.text("Display and system"), subtitle: L10n.text("Kiwi uses temporary system power assertions and releases them when work ends.")) {
                Toggle(L10n.text("Keep the display on during a session"), isOn: $model.keepDisplayAwake)
                Text(L10n.text("When this is off, the display may turn off while the Mac stays awake for work. This saves battery."))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: L10n.text("AI agent connection"), subtitle: L10n.text("Local hooks can tell Kiwi when work starts, send heartbeats, and report completion.")) {
                Toggle(L10n.text("Allow events from local hooks"), isOn: $model.agentBridgeEnabled)
                Text(L10n.text("The bridge is off by default. Only trust installed hooks: any local process that can open the URL scheme can send an event. Without a heartbeat, a session expires after 3 minutes. Agent events never trigger immediate sleep."))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.text("From the repository root: ./Scripts/agent-session.sh my-agent-1 -- ./run-agent.sh\nFor IDE hooks: agent-event.sh start > heartbeat (about once a minute) > done or failed; use one ID per session."))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if model.activeAgentCount > 0 {
                    Label(L10n.format("Active now: %d", model.activeAgentCount), systemImage: "cpu")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: 0x5EAC70))
                }
            }

            SettingsCard(title: L10n.text("Launch at login"), subtitle: L10n.text("Useful if Kiwi is part of your everyday work setup.")) {
                Toggle(L10n.text("Launch Sweet No Sleep at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLoginItem(enabled: enabled)
                    }

                Toggle(L10n.text("Enable manual sleep protection at launch"), isOn: $model.resumeKeepAwakeOnLaunch)
                Text(L10n.text("Leave this off if you do not want to use battery after a restart."))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let loginMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(loginMessage, systemImage: loginNeedsApproval ? "gearshape.2" : "info.circle")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(loginNeedsApproval ? Color(hex: 0xD99142) : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if loginNeedsApproval {
                            Button(L10n.text("Open Login Items")) {
                                SMAppService.openSystemSettingsLoginItems()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }

            if let warning = model.powerWarning {
                SettingsCard(title: L10n.text("Power status")) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color(hex: 0xD99142))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear(perform: refreshLoginItemState)
    }

    private func refreshLoginItemState() {
        guard #available(macOS 13.0, *) else {
            launchAtLogin = false
            return
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        if status == .requiresApproval {
            loginNeedsApproval = true
            loginMessage = L10n.text("macOS is waiting for approval in System Settings > General > Login Items.")
        } else {
            loginNeedsApproval = false
            loginMessage = nil
        }
    }

    private func updateLoginItem(enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            loginMessage = L10n.text("Launch at login requires macOS 13 or later.")
            launchAtLogin = false
            return
        }

        do {
            let service = SMAppService.mainApp
            if enabled {
                if service.status == .requiresApproval {
                    loginNeedsApproval = true
                    loginMessage = L10n.text("Allow Sweet No Sleep in System Settings > General > Login Items.")
                } else if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            refreshLoginItemState()
        } catch {
            loginMessage = L10n.format("Could not update launch at login: %@", error.localizedDescription)
            loginNeedsApproval = false
            launchAtLogin = false
        }
    }
}

// MARK: - Shared settings components

private struct SettingsScrollPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 23)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsHero: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: 0x5EAC70))
                .frame(width: 40, height: 40)
                .background(Color(hex: 0x70BF7E, opacity: 0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.primary.opacity(0.075), lineWidth: 1)
        }
    }
}
