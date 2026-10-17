import AppKit
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

@main
struct TimetrackMacApp: App {
    @State private var model: AppModel
    @State private var ui = UIState()

    init() {
        let passkeys = PlatformPasskeyAuthenticator { NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow() }
        let auth = AuthService(secrets: KeychainSecretStore(), transport: URLSessionTransport(), passkeys: passkeys)
        let model = AppModel(auth: auth)
        model.onOutcome = { TTHaptics.handle($0) } // trackpad feedback for explicit actions only
        _model = State(initialValue: model)
    }

    var body: some Scene {
        Window("Timetrack", id: "main") {
            RootView()
                .environment(model)
                .environment(ui)
                .widgetSync(model) // A7: widget snapshot
                .frame(minWidth: 760, minHeight: 480)
                .ttAppearance()
                .task {
                    await model.restore()
                    #if DEBUG
                    await DebugSnapshots.run(model: model, ui: ui)
                    #endif
                }
        }
        .commands { TimetrackCommands(model: model, ui: ui) }

        MenuBarExtra("Timetrack", systemImage: model.today?.running == nil ? "clock" : "clock.fill") {
            MenuBarContent()
                .environment(model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(model)
                .ttAppearance()
        }
    }
}

@MainActor
@Observable
final class UIState {
    var selection: SidebarItem = .today
    var newEntryRequest = 0
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case today, time, calendar, vacation
    var id: String { rawValue }

    /// Module that must be on for this entry; `nil` = core feature that is always available.
    var requiredModule: ModuleKey? { self == .calendar || self == .vacation ? .planning : nil }

    var titleKey: LocalizedStringKey {
        switch self {
        case .today: "sidebar.today"
        case .time: "sidebar.time"
        case .calendar: "sidebar.calendar"
        case .vacation: "sidebar.vacation"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .time: "calendar.day.timeline.left"
        case .calendar: "calendar"
        case .vacation: "beach.umbrella"
        }
    }
}

struct TimetrackCommands: Commands {
    let model: AppModel
    let ui: UIState

    var body: some Commands {
        CommandMenu("menu.time") {
            Button(model.today?.running == nil ? "command.start" : "command.stop") {
                Task { @MainActor in await toggleTimer(model) }
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(model.today == nil)

            Divider()

            Button("command.new_entry") {
                ui.selection = .time
                ui.newEntryRequest += 1
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(model.phase != .signedIn)

            Button("command.reload") {
                Task { @MainActor in
                    await model.today?.load()
                    await model.timeList?.load()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.phase != .signedIn)
        }
        CommandGroup(after: .sidebar) {
            Button("sidebar.today") { ui.selection = .today }.keyboardShortcut("1", modifiers: .command)
            Button("sidebar.time") { ui.selection = .time }.keyboardShortcut("2", modifiers: .command)
        }
    }
}

@MainActor
func toggleTimer(_ model: AppModel) async {
    guard let today = model.today else { return }
    if today.running == nil { await today.start() } else { await today.stop() }
}
