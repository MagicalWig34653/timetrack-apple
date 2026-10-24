import AppKit
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

@main
struct TimetrackMacApp: App {
    @State private var model: AppModel
    @State private var ui = UIState()
    @State private var deviceCalendar = CalendarEnvironment.makeStore() // M2: device calendars (EventKit), read-only by default
    @AppStorage(MacPrefs.menuBarInserted) private var menuBarInserted = true
    @AppStorage(MacPrefs.menuBarOnly) private var menuBarOnly = false

    init() {
        let passkeys = PlatformPasskeyAuthenticator { NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow() }
        let auth = AuthService(secrets: KeychainSecretStore(), transport: URLSessionTransport(), passkeys: passkeys)
        let model = AppModel(auth: auth)
        model.onOutcome = { TTHaptics.handle($0) } // trackpad feedback for explicit actions only
        MacNotifications.install() // M2: answers to "Timer beenden?" / "Timer starten?"
        _model = State(initialValue: model)
    }

    var body: some Scene {
        Window("Timetrack", id: "main") {
            RootView()
                .environment(model)
                .environment(ui)
                .environment(\.deviceCalendar, deviceCalendar)
                .widgetSync(model) // A7: widget snapshot
                .frame(minWidth: 900, minHeight: 560)
                .ttAppearance()
                .debugSettingsOpener()
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["TT_DEV_M2"] == "1" { await DebugSnapshots.run(model: model, ui: ui); return }
                    #endif
                    await MacBootstrap.run(model)
                    #if DEBUG
                    await DebugSnapshots.run(model: model, ui: ui)
                    #endif
                }
        }
        .defaultSize(width: 1100, height: 720)
        // M2: in "nur Menüleiste" mode the window is not opened at launch; the menu bar item opens it on demand.
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: MacPrefs.menuBarOnly) ? .suppressed : .presented)
        .commands { TimetrackCommands(model: model, ui: ui) }

        MenuBarExtra(isInserted: Binding(get: { menuBarInserted || menuBarOnly }, set: { menuBarInserted = $0 })) {
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
                .environment(\.deviceCalendar, deviceCalendar)
                .ttAppearance()
        }
    }
}

@MainActor
@Observable
final class UIState {
    var selection: SidebarItem = .today
    /// M2: day shown in the "Aktivität" view.
    /// Pending command for the "Zeit" screen; `serial` changes on every send so repeated commands are noticed.
    var timeCommand: TimeCommand?
    var timeCommandSerial = 0
    var inspectorVisible = true
    /// BH1: week the Berichtsheft opens on (set by "Berichtsheft für diese Woche" in the Zeit screen; nil = current week).
    var reportsWeek: ReportWeekRef?
    /// H5: "Fortführen" with a long gap asks first (window-wide dialog, so the menu command works from every screen).
    var continueChoice = false

    func send(_ command: TimeCommand) {
        selection = .time
        timeCommand = command
        timeCommandSerial += 1
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case today, time, planning, calendar, vacation, reports, activity
    var id: String { rawValue }

    /// Module that must be on for this entry; `nil` = core feature that is always available.
    var requiredModule: ModuleKey? {
        switch self {
        case .planning, .calendar, .vacation: .planning
        case .reports: .reports
        case .today, .time, .activity: nil
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .today: "sidebar.today"
        case .time: "sidebar.time"
        case .planning: "sidebar.planning"
        case .calendar: "sidebar.calendar"
        case .vacation: "sidebar.vacation"
        case .reports: "sidebar.reports"
        case .activity: "Aktivität"
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
        case .reports: "book.closed"
        case .activity: "square.stack.3d.up"
        }
    }
}

/// M2: start-up work that must also happen when the app launches "nur Menüleiste" (no window, so no window task): the menu bar label runs it too.
@MainActor
enum MacBootstrap {
    private static var running = false

    static func run(_ model: AppModel) async {
        MacCompanion.shared.attach(model) // activity capture, presence, hotkey, Dock mode
        MacAutomationRuntime.shared.start()
        await model.restoreIfNeeded() // HG1: no teardown of an already signed-in UI when this runs again
        guard !running else { return }
        running = true
        defer { running = false }
        await MacAutomationRuntime.shared.refreshPlaces(using: model.apiClient)
    }
}
