import SwiftUI
import ServiceManagement

// Pet size options shown in the settings picker.
enum PetSize: String, CaseIterable, Identifiable {
    case small = "S"
    case medium = "M"
    case large = "L"

    var id: String { rawValue }

    // Display label for the picker.
    var label: String {
        switch self {
        case .small:
            return NSLocalizedString("settings.petSize.small", comment: "Small pet size")
        case .medium:
            return NSLocalizedString("settings.petSize.medium", comment: "Medium pet size")
        case .large:
            return NSLocalizedString("settings.petSize.large", comment: "Large pet size")
        }
    }

    // Circle diameter in points.
    var diameter: CGFloat {
        switch self {
        case .small:
            return 80
        case .medium:
            return 120
        case .large:
            return 170
        }
    }
}

// Settings form: login item, start-awake flag, and pet size.
struct SettingsView: View {
    @AppStorage("startAwake") private var startAwake: Bool = true
    @AppStorage("petSize") private var petSizeRaw: String = PetSize.medium.rawValue
    @State private var launchAtLogin: Bool = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(
                    NSLocalizedString("settings.launchAtLogin", comment: "Launch at login toggle"),
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(enabled: newValue)
                }
                Toggle(
                    NSLocalizedString("settings.startAwake", comment: "Start awake toggle"),
                    isOn: $startAwake
                )
                Picker(
                    NSLocalizedString("settings.petSize", comment: "Pet size picker"),
                    selection: $petSizeRaw
                ) {
                    ForEach(PetSize.allCases) { size in
                        Text(size.label).tag(size.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(NSLocalizedString("settings.general", comment: "General section header"))
            }
            if let message = loginError {
                Section {
                    Text(message).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 280, minHeight: 180)
        .onAppear {
            launchAtLogin = currentLoginItemState()
        }
    }

    // Best-effort login-item state. Never crashes when unavailable.
    private func currentLoginItemState() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    // Best-effort login-item update. Records an error instead of crashing.
    private func setLaunchAtLogin(enabled: Bool) {
        loginError = nil
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                loginError = error.localizedDescription
                launchAtLogin = currentLoginItemState()
            }
        } else {
            loginError = NSLocalizedString(
                "settings.loginUnsupported",
                comment: "Login item unsupported on this macOS"
            )
            launchAtLogin = false
        }
    }
}
