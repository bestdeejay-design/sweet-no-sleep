import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SweetNoSleepModel

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                FocusSettingsPane(model: model)
                    .tabItem { Label(L10n.text("Focus"), systemImage: "bolt.fill") }
                CompanionSettingsPane(model: model)
                    .tabItem { Label(L10n.text("Pet"), systemImage: "pawprint.fill") }
                PowerSettingsPane(model: model)
                    .tabItem { Label(L10n.text("Power"), systemImage: "battery.100percent") }
            }
            HStack(spacing: 10) {
                Picker(selection: $model.overrideLanguage, label: EmptyView()) {
                    Text(L10n.text("System language")).tag("")
                    Text("English").tag("en")
                    Text("\u{0420}\u{0443}\u{0441}\u{0441}\u{043a}\u{0438}\u{0439}").tag("ru")
                    Text("Español").tag("es")
                    Text("\u{d55c}\u{ad6d}\u{c5b4}").tag("ko")
                    Text("\u{4e2d}\u{6587}").tag("zh-Hans")
                    Text("\u{65e5}\u{672c}\u{8a9e}").tag("ja")
                }
                .labelsHidden()
                .font(.system(size: 11, design: .rounded))
                .frame(width: 150)
                Spacer()
                Text(L10n.format("Version %@ (build %@)", version, build))
                    .font(.system(size: 10, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
            HStack(spacing: 6) {
                Text(L10n.format("Interface language: %@", L10n.text("System language")))
                    .font(.system(size: 9, design: .rounded))
                Spacer()
                Text("Sweet No Sleep")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .frame(width: 660, height: 555)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
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
                subtitle: L10n.format("Start a session manually and choose what %@ should do when it ends.", model.characterName)
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
                    Text(SessionCompletionAction.allowNormalSleep.detail(persona: model.characterName))
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
                title: L10n.format("%@'s personality", model.characterName),
                subtitle: L10n.format("Choose %@'s look and how visibly the pet joins your workday.", model.characterName)
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
                Text(L10n.text("New packs in that folder appear in the picker automatically; Refresh list still works."))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: L10n.text("Pet size"), subtitle: L10n.format("Current size: %d pt - changes apply immediately on the desktop.", Int(model.petSize))) {
                Slider(value: sizeBinding, in: 45...170, step: 1)
                    .tint(Color(hex: 0x74C987))
                    .accessibilityLabel(L10n.text("Pet size"))
                HStack {
                    Text(L10n.text("45 pt - compact"))
                    Spacer()
                    Text(L10n.text("170 pt - large"))
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                Label(L10n.text("Drag the pet to place it wherever it feels comfortable."), systemImage: "hand.draw")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: L10n.text("Behavior"), subtitle: L10n.format("Adjust how %@ moves and which playful moments appear during an awake session.", model.characterName)) {
                Toggle(L10n.text("Roam gently across the screen"), isOn: $model.roamingEnabled)
                Label(L10n.text("The first stroll starts about 3 seconds after enabling; later strolls begin about every 28 seconds."), systemImage: "figure.walk")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                Toggle(L10n.text("Keep above other windows"), isOn: $model.alwaysOnTop)
                Toggle(L10n.text("Breathing, blinking, and movement"), isOn: $model.animationsEnabled)
                Toggle(L10n.text("Occasional dances, stretches, and curious looks"), isOn: $model.playfulMomentsEnabled)
                    .disabled(!model.animationsEnabled)

                if model.playfulMomentsEnabled && model.animationsEnabled {
                    HStack(spacing: 10) {
                        Text(L10n.format("About every %d sec", model.playfulMomentIntervalSeconds))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .frame(width: 120, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(model.playfulMomentIntervalSeconds) },
                            set: { model.playfulMomentIntervalSeconds = Int($0) }
                        ), in: 15...120, step: 15)
                        .tint(Color(hex: 0x74C987))
                        .accessibilityLabel(L10n.text("Playful moment interval"))
                    }
                    Label(L10n.text("The exact delay varies slightly within 60 to 120 seconds."), systemImage: "timer")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(L10n.text("Mood weights - higher values make a mood more likely; 0 turns it off."))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                    playfulWeightRow(
                        title: L10n.text("Dancing"),
                        accessibilityLabel: L10n.text("Dancing mood weight"),
                        weight: $model.playfulDancingWeight
                    )
                    playfulWeightRow(
                        title: L10n.text("Stretching"),
                        accessibilityLabel: L10n.text("Stretching mood weight"),
                        weight: $model.playfulStretchingWeight
                    )
                    playfulWeightRow(
                        title: L10n.text("Curious"),
                        accessibilityLabel: L10n.text("Curious mood weight"),
                        weight: $model.playfulCuriousWeight
                    )
                }

                Label(L10n.format("%@'s eyes follow the pointer automatically.", model.characterName), systemImage: "eye")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: L10n.text("Eye and attention breaks"), subtitle: L10n.format("During an awake session, %@ gently suggests looking away from code and into the distance for about 20 seconds.", model.characterName)) {
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
                Toggle(L10n.format("Show %@ on the desktop", model.characterName), isOn: $model.isPetVisible)
            }
        }
    }

    private func playfulWeightRow(title: String, accessibilityLabel: String, weight: Binding<Int>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .frame(width: 120, alignment: .leading)
            Slider(value: Binding(
                get: { Double(weight.wrappedValue) },
                set: { weight.wrappedValue = Int($0) }
            ), in: 0...10, step: 1)
            .tint(Color(hex: 0x74C987))
            .accessibilityLabel(accessibilityLabel)
            Text("\(weight.wrappedValue)")
                .font(.system(size: 10, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
        }
    }

    private func skinChoice(_ skin: PetSkinDefinition) -> some View {
        let palette = PetPalette.palette(for: skin)
        let preview = MediaAssets.skinPreview(for: skin.id)
        let isSelected = model.selectedSkinID == skin.id
        return Button {
            model.selectedSkinID = skin.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let preview {
                            Image(nsImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            skinSwatchesPreview(palette)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(hex: 0x5BAF70))
                            .padding(7)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
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
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func skinSwatchesPreview(_ palette: PetPalette) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.fur.opacity(0.22))
            Circle()
                .fill(palette.fur)
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(palette.outline)
                }
            HStack(spacing: 7) {
                Circle().fill(palette.fur).frame(width: 13, height: 13)
                Circle().fill(palette.accent).frame(width: 13, height: 13)
                Circle().fill(palette.cheek).frame(width: 13, height: 13)
            }
            .padding(6)
            .background(.white.opacity(0.85), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(7)
        }
        .aspectRatio(1.5, contentMode: .fit)
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

            SettingsCard(title: L10n.text("Display and system"), subtitle: L10n.format("%@ uses temporary system power assertions and releases them when work ends.", model.characterName)) {
                Toggle(L10n.text("Keep the display on during a session"), isOn: $model.keepDisplayAwake)
                Text(L10n.text("When this is off, the display may turn off while the Mac stays awake for work. This saves battery."))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: L10n.text("Battery safety floor"), subtitle: L10n.text("Pause sleep protection when battery charge drops below a safe level. Protection resumes when plugged in.")) {
                HStack(spacing: 10) {
                    Text(model.batteryFloorPercent == 0 ? L10n.text("Disabled (0%)") : L10n.format("%d%% (pause below)", model.batteryFloorPercent))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .frame(width: 140, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(model.batteryFloorPercent) },
                        set: { model.batteryFloorPercent = Int($0) }
                    ), in: 0...50, step: 5)
                    .tint(Color(hex: 0x74C987))
                    .accessibilityLabel(L10n.text("Battery safety floor percentage"))
                }
                HStack {
                    Text(L10n.text("0% (Disabled)"))
                    Spacer()
                    Text(L10n.text("50%"))
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                Text(L10n.text("Desktops and plugged-in MacBooks are not affected."))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: L10n.text("Continuous awake cap"), subtitle: L10n.text("Automatically release assertions after continuous awake time to prevent battery drain from forgotten sessions.")) {
                HStack(spacing: 10) {
                    Text(model.continuousAwakeCapHours == 0 ? L10n.text("Disabled") : L10n.format("%d hours", model.continuousAwakeCapHours))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .frame(width: 140, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(model.continuousAwakeCapHours) },
                        set: { model.continuousAwakeCapHours = Int($0) }
                    ), in: 0...12, step: 1)
                    .tint(Color(hex: 0x74C987))
                    .accessibilityLabel(L10n.text("Continuous awake cap in hours"))
                }
                HStack {
                    Text(L10n.text("Disabled (0h)"))
                    Spacer()
                    Text(L10n.text("12 hours"))
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                Text(L10n.text("Uses monotonic system uptime; pauses while the Mac is asleep."))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            SettingsCard(title: L10n.text("Hold diagnostics"), subtitle: L10n.text("Live status of power assertions, battery polling, and kernel timers.")) {
                VStack(alignment: .leading, spacing: 6) {
                    diagnosticSettingsRow(
                        label: L10n.text("System assertion"),
                        value: model.diagnostics.isSystemActive
                            ? L10n.format("Active (ID: %u)", model.diagnostics.systemAssertionID)
                            : L10n.text("Inactive")
                    )
                    diagnosticSettingsRow(
                        label: L10n.text("Display assertion"),
                        value: model.diagnostics.isDisplayActive
                            ? L10n.format("Active (ID: %u)", model.diagnostics.displayAssertionID)
                            : L10n.text("Inactive")
                    )
                    if model.diagnostics.isSystemActive || model.diagnostics.isDisplayActive {
                        diagnosticSettingsRow(
                            label: L10n.text("Next re-arm"),
                            value: L10n.format("%d s", model.diagnostics.secondsUntilRearm)
                        )
                    }
                    diagnosticSettingsRow(
                        label: L10n.text("Power source"),
                        value: model.diagnostics.batteryDescription
                    )
                    diagnosticSettingsRow(
                        label: L10n.text("Last power event"),
                        value: model.diagnostics.lastPowerEvent
                    )
                    diagnosticSettingsRow(
                        label: L10n.text("Awake sources"),
                        value: model.diagnostics.awakeSources
                    )
                }
            }

            SettingsCard(title: L10n.text("AI agent connection"), subtitle: L10n.format("Local hooks can tell %@ when work starts, send heartbeats, report completion, or ask for your approval.", model.characterName)) {
                Toggle(L10n.text("Allow events from local hooks"), isOn: $model.agentBridgeEnabled)
                Text(L10n.text("The bridge is off by default. Only trust installed hooks: any local process that can open the URL scheme can send an event. Without a heartbeat, a session expires after 3 minutes. Agent events never trigger immediate sleep."))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.text("From the repository root: ./Scripts/agent-session.sh my-agent-1 -- ./run-agent.sh\nFor IDE hooks: agent-event.sh start > heartbeat (about once a minute) > waiting when a question needs you > done or failed; use one ID per session."))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer(minLength: 4)
                    Button(L10n.text("Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(L10n.text("From the repository root: ./Scripts/agent-session.sh my-agent-1 -- ./run-agent.sh\nFor IDE hooks: agent-event.sh start > heartbeat (about once a minute) > waiting when a question needs you > done or failed; use one ID per session."), forType: .string)
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Toggle(L10n.text("Show the status light and active-agent count on the pet"), isOn: $model.agentIndicatorEnabled)
                    .disabled(!model.agentBridgeEnabled)
                Text(L10n.text("The chest badge shows a green light while agents work, an amber light when one waits for your answer, and the number of active sessions right below it."))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.hasWaitingAgent {
                    Label(
                        model.agentWaitingReason.map { L10n.format("Waiting for your answer: %@", $0) }
                            ?? L10n.text("An agent is waiting for your answer (y/n)."),
                        systemImage: "questionmark.circle.fill"
                    )
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AgentIndicator.waitingColor)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if model.activeAgentCount > 0 {
                    Label(L10n.format("Active now: %d", model.activeAgentCount), systemImage: "cpu")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: 0x5EAC70))
                    ForEach(model.agentSessionSummaries) { session in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(session.isWaiting ? AgentIndicator.waitingColor : Color(hex: 0x7ED18A))
                                .frame(width: 6, height: 6)
                            Text(session.shortID)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                            Text(session.isWaiting ? L10n.text("Waiting for your answer") : L10n.text("Working"))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            SettingsCard(title: L10n.text("Local webhook"), subtitle: L10n.text("Loopback-only HTTP listener on 127.0.0.1:18290 for sandboxed runners that cannot open URL schemes.")) {
                Toggle(L10n.text("Enable localhost webhook"), isOn: $model.agentWebhookEnabled)
                    .disabled(!model.agentBridgeEnabled)
                HStack(spacing: 8) {
                    Text(model.agentWebhookToken)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    Button(L10n.text("Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.agentWebhookToken, forType: .string)
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Button(L10n.text("New token")) {
                        model.regenerateWebhookToken()
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Text(L10n.text("POST to http://127.0.0.1:18290/agent/<start|heartbeat|waiting|done|failed> with a JSON body {\"session\": \"id\", \"reason\": \"text\"} and the Authorization: Bearer header. Same 3-minute lease as the URL bridge."))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let webhookError = model.agentWebhookError {
                    Label(webhookError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: 0xD99142))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard(title: L10n.text("Launch at login"), subtitle: L10n.format("Useful if %@ is part of your everyday work setup.", model.characterName)) {
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

    private func diagnosticSettingsRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
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
