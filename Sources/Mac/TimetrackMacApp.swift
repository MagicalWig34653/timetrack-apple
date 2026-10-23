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
                .frame(minWidth: 900, minHeight: 560)
                .ttAppearance()
                .debugSettingsOpener()
                .task {
                    await model.restoreIfNeeded() // HG1: no teardown of an already signed-in UI when this task runs again
                    #if DEBUG
                    await DebugSnapshots.run(model: model, ui: ui)
                    #endif
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands { TimetrackCommands(model: model, ui: ui) }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
                .ttAppearance()
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)

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
    /// Pending command for the "Zeit" screen; `serial` changes on every send so repeated commands are noticed.
    var timeCommand: TimeCommand?
    var timeCommandSerial = 0
    var inspectorVisible = true
    /// H5: "Fortführen" with a long gap asks first (window-wide dialog, so the menu command works from every screen).
    var continueChoice = false

    func send(_ command: TimeCommand) {
        selection = .time
        timeCommand = command
        timeCommandSerial += 1
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case today, time, planning, calendar, vacation
    var id: String { rawValue }

    /// Module that must be on for this entry; `nil` = core feature that is always available.
    var requiredModule: ModuleKey? { self == .planning || self == .calendar || self == .vacation ? .planning : nil }

    var titleKey: LocalizedStringKey {
        switch self {
        case .today: "sidebar.today"
        case .time: "sidebar.time"
        case .planning: "sidebar.planning"
        case .calendar: "sidebar.calendar"
        case .vacation: "sidebar.vacation"
        }
    }

    /// Sidebar section: capturing time vs. planning.
    var isPlanning: Bool { self == .planning || self == .calendar || self == .vacation }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .time: "calendar.day.timeline.left"
        case .planning: "calendar.badge.checkmark"
        case .calendar: "calendar"
        case .vacation: "beach.umbrella"
        }
    }
}
