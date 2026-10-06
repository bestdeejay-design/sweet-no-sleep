import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SweetNoSleepModel

    var body: some View {
        TabView {
            FocusSettingsPane(model: model)
                .tabItem { Label("Фокус", systemImage: "bolt.fill") }
            CompanionSettingsPane(model: model)
                .tabItem { Label("Питомец", systemImage: "pawprint.fill") }
            PowerSettingsPane(model: model)
                .tabItem { Label("Питание", systemImage: "battery.100percent") }
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
                title: "Фокус без внезапного сна",
                subtitle: "Запускайте сессию вручную и выбирайте, что Киви сделает по её завершении."
            )

            SettingsCard(title: "Длительность", subtitle: "Сейчас выбрано: \(model.selectedMinutes) минут") {
                Slider(value: durationBinding, in: 15...240, step: 5)
                    .tint(Color(hex: 0x74C987))
                    .accessibilityLabel("Длительность сессии в минутах")
                HStack {
                    Text("15 мин")
                    Spacer()
                    Text("4 часа")
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
            }

            SettingsCard(title: "Когда цель достигнута", subtitle: "Для начала рекомендуем безопасный вариант — обычный сон по настройкам macOS.") {
                Picker("Действие после сессии", selection: $model.completionAction) {
                    ForEach(SessionCompletionAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.completionAction == .sleepImmediately {
                    Label(
                        "Перед каждой такой сессией появится подтверждение. Немедленный сон может прервать другие приложения и агентов.",
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

            SettingsCard(title: "Быстрый переключатель", subtitle: "Переключатель показывает фактическое состояние и завершает любую текущую сессию.") {
                Toggle(isOn: Binding(
                    get: { model.isKeepingAwake },
                    set: { model.setKeepAwake($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Не давать Mac заснуть")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("Удерживать систему бодрствующей до выключения вручную")
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
                title: "Характер Киви",
                subtitle: "Выберите образ и то, насколько заметно питомец будет жить рядом с вашей работой."
            )

            SettingsCard(title: "Скин", subtitle: "Архитектура уже разделяет внешний вид и поведение — новые питомцы смогут подключаться отдельно.") {
                HStack(spacing: 10) {
                    ForEach(KiwiSkin.allCases) { skin in
                        skinChoice(skin)
                    }
                }
            }

            SettingsCard(title: "Размер на рабочем столе", subtitle: "\(Int(model.petSize)) pt · перетащите Киви в удобное место") {
                Slider(value: sizeBinding, in: 90...170, step: 2)
                    .tint(Color(hex: 0x74C987))
                    .accessibilityLabel("Размер питомца")
                HStack {
                    Text("Компактный")
                    Spacer()
                    Text("Крупный")
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
            }

            SettingsCard(title: "Поведение", subtitle: "Ненавязчиво по умолчанию; все движения можно отключить.") {
                Toggle("Плавно гулять по экрану", isOn: $model.roamingEnabled)
                Toggle("Показывать поверх окон", isOn: $model.alwaysOnTop)
                Toggle("Дыхание, моргание и реакции", isOn: $model.animationsEnabled)
            }

            SettingsCard(title: "Рабочий слой", subtitle: "Окно питомца прозрачное и не перехватывает фокус у редактора кода.") {
                Toggle("Показывать Киви на рабочем столе", isOn: $model.isPetVisible)
            }
        }
    }

    private func skinChoice(_ skin: KiwiSkin) -> some View {
        let palette = PetPalette.palette(for: skin)
        let isSelected = model.skin == skin
        return Button {
            model.skin = skin
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
                Text(skin.title)
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
        .accessibilityLabel("Скин: \(skin.title)")
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
                title: "Питание и запуск",
                subtitle: "Защита от сна действует только пока включён режим бодрствования или идёт таймер."
            )

            SettingsCard(title: "Экран и система", subtitle: "Киви использует временные системные power assertions и освобождает их по завершении.") {
                Toggle("Не выключать дисплей во время сессии", isOn: $model.keepDisplayAwake)
                Text("Если переключатель выключен, экран может погаснуть, но Mac и выполняемая работа не должны уснуть из-за бездействия. Это экономит батарею.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: "Связь с AI-агентами", subtitle: "Локальные hooks могут сообщать Киви о начале, heartbeat и завершении работы.") {
                Toggle("Разрешить события от локальных hooks", isOn: $model.agentBridgeEnabled)
                Text("Bridge выключен по умолчанию. Доверяйте установленным hooks: любой локальный процесс с доступом к URL scheme может послать событие. Без heartbeat сессия завершится через 3 минуты; agent-событие не запускает немедленный сон.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.activeAgentCount > 0 {
                    Label("Сейчас активно: \(model.activeAgentCount)", systemImage: "cpu")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: 0x5EAC70))
                }
            }

            SettingsCard(title: "Автозапуск", subtitle: "Удобно, если Киви — часть ежедневной рабочей среды.") {
                Toggle("Запускать Sweet No Sleep при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLoginItem(enabled: enabled)
                    }

                Toggle("Сразу включать ручную защиту от сна", isOn: $model.resumeKeepAwakeOnLaunch)
                Text("Оставьте автозащиту выключенной, если не хотите расходовать батарею после перезагрузки.")
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
                            Button("Открыть «Объекты входа»") {
                                SMAppService.openSystemSettingsLoginItems()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }

            if let warning = model.powerWarning {
                SettingsCard(title: "Состояние питания") {
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
            loginMessage = "macOS ожидает подтверждения в Системных настройках → Основные → Объекты входа."
        } else {
            loginNeedsApproval = false
            loginMessage = nil
        }
    }

    private func updateLoginItem(enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            loginMessage = "Для автозапуска требуется macOS 13 или новее."
            launchAtLogin = false
            return
        }

        do {
            let service = SMAppService.mainApp
            if enabled {
                if service.status == .requiresApproval {
                    loginNeedsApproval = true
                    loginMessage = "Разрешите Sweet No Sleep в Системных настройках → Основные → Объекты входа."
                } else if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            refreshLoginItemState()
        } catch {
            loginMessage = "Не удалось изменить автозапуск: \(error.localizedDescription)"
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
