import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

extension EnvironmentValues {
    /// The app-wide sender that hands the session to the Apple Watch (nil in previews).
    @Entry var watchSender: WatchHandoffSender?
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.watchSender) private var watchSender
    @State private var confirmingServerChange = false
    @State private var watchStatus: WatchHandoffResult?
    @State private var showingVacation = false
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                AccountCard()
                // SET-A: same groups, names and descriptions as the web app (SettingsStructure in the core package).
                SettingsGroupsView(groups: groups) { entry in row(entry) }
                watchStatusLine
                sessionActions
            }
            .settingsPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("sidebar.settings")
        .searchable(text: $query, prompt: "Einstellung suchen …")
        .confirmationDialog("settings.change_server.confirm", isPresented: $confirmingServerChange, titleVisibility: .visible) {
            Button("settings.change_server", role: .destructive) { Task { await model.forgetServer() } }
        }
        .ttHaptic(.confirmDestructive, whenBecomesTrue: confirmingServerChange)
        .sheet(isPresented: $showingVacation) {
            if let store = model.planning { VacationSettingsSheet(store: store) }
        }
    }

    // MARK: - Structure

    /// Visible groups: module state and platform from the core structure, minus entries that cannot work right now.
    private var groups: [SettingsGroup] {
        SettingsStructure.groups(platform: .iOS, isEnabled: { model.isEnabled($0) }, query: query).compactMap { group in
            let entries = group.entries.filter { entry in
                switch entry.id {
                case .appleWatch: watchSender != nil
                case .export: model.serverURL != nil
                case .vacationEntitlement: model.planning != nil
                default: true
                }
            }
            return entries.isEmpty ? nil : SettingsGroup(id: group.id, entries: entries)
        }
    }

    @ViewBuilder private func row(_ entry: SettingsEntry) -> some View {
        switch entry.id {
        case .vacationEntitlement:
            Button {
                // Load before presenting: saving the sheet writes all fields, so it must start from the server values.
                Task {
                    guard let store = model.planning else { return }
                    await store.load(); await store.loadSettings(); showingVacation = true
                }
            } label: { SettingsEntryLabel(entry: entry) }
                .buttonStyle(.plain).accessibilityIdentifier(entry.id.accessibilityID)
        case .appleWatch:
            Button { if let watchSender { Task { watchStatus = await watchSender.sendNow() } } } label: { SettingsEntryLabel(entry: entry, chevron: "arrow.up.circle") }
                .buttonStyle(.plain).accessibilityIdentifier(entry.id.accessibilityID)
        case .export:
            if let url = model.serverURL?.appending(path: "export") { // the PWA route of the page
                Link(destination: url) { SettingsEntryLabel(entry: entry, chevron: "arrow.up.right") }
                    .buttonStyle(.plain).accessibilityIdentifier(entry.id.accessibilityID)
                    .accessibilityHint(Text("Öffnet die Web-App im Browser"))
            }
        default:
            NavigationLink { destination(entry.id) } label: { SettingsEntryLabel(entry: entry, value: value(entry.id)) }
                .buttonStyle(.plain).accessibilityIdentifier(entry.id.accessibilityID)
        }
    }

    @ViewBuilder private func destination(_ id: SettingsEntryID) -> some View {
        switch id {
        case .profile: ProfilePage()
        case .passkeys: PasskeysPage()
        case .identities: IdentitiesPage()
        case .recovery: RecoveryPage()
        case .sessions: SessionsPage()
        case .workModel: WorkModelsScreen()
        case .accountTime: TimeAccountScreen() // WM2
        case .learningFields: LearningFieldsScreen()
        case .sharing: SharingScreen()
        case .places: AutomationSettingsView()
        case .triggerLinks: TriggerLinksPage() // AUD3-A
        case .focusFilter: FocusFilterView()
        case .notifications: PushSettingsPage() // P14c
        case .vacationReminders: VacationReminderSettingsView() // R3
        case .overworkHints: OverworkSettingsView() // OT1
        case .calendarFeeds: CalendarFeedsPage()
        case .deviceCalendar: CalendarSettingsView()
        case .cancelled: CancelledScreen()
        case .appearance: AppearanceView()
        case .modules: ServerModulesView()
        case .about: AboutView()
        case .vacationEntitlement, .export, .appleWatch, .menuBar, .activity: EmptyView()
        }
    }

    /// Short state next to a row (the page explains the rest).
    private func value(_ id: SettingsEntryID) -> String? {
        switch id {
        case .notifications: pushValue
        case .about: AppBuildInfo(platform: "iOS").display
        default: nil
        }
    }

    private var pushValue: String? {
        guard let push = model.push else { return nil }
        switch push.state {
        case .registered: return "Aktiv"
        case .unavailable: return "Nicht angeboten"
        case .idle, .registering: return nil
        case .limitReached, .systemFailure, .failed: return "Problem"
        }
    }

    @ViewBuilder private var watchStatusLine: some View {
        if let watchStatus {
            HStack {
                StatusChip(Self.statusKey(watchStatus), tone: watchStatus == .sent ? .success : .neutral, symbol: Self.statusSymbol(watchStatus))
                Spacer()
            }
            .accessibilityIdentifier("settings.watch.status")
        }
    }

    private var sessionActions: some View {
        VStack(spacing: TT.Space.m) {
            Button { Task { await model.signOut() } } label: { Label("account.sign_out", systemImage: "rectangle.portrait.and.arrow.right") }
                .buttonStyle(.ttSecondary)
                .accessibilityIdentifier("settings.sign_out")
            Button("settings.change_server", role: .destructive) { confirmingServerChange = true }
                .font(TTFont.label)
                .foregroundStyle(TT.danger)
        }
    }

    static func statusKey(_ result: WatchHandoffResult) -> LocalizedStringKey {
        switch result {
        case .notPaired: "settings.watch.status.not_paired"
        case .notSignedIn: "settings.watch.status.not_signed_in"
        case .queuedUnreachable: "settings.watch.status.unreachable"
        case .sent: "settings.watch.status.sent"
        case .failed: "settings.watch.status.failed"
        }
    }

    private static func statusSymbol(_ result: WatchHandoffResult) -> String {
        switch result {
        case .sent: "checkmark.circle"
        case .queuedUnreachable: "clock"
        case .notPaired, .notSignedIn, .failed: "exclamationmark.circle"
        }
    }
}

/// Name and handle of the signed-in account (top of "Mehr" and of the settings).
struct AccountCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.ttTheme) private var theme

    var body: some View {
        if let account = model.account {
            Card {
                HStack(spacing: TT.Space.l) {
                    Text(verbatim: String(account.displayName.prefix(1)).uppercased())
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(theme.onAccent)
                        .frame(width: 56, height: 56)
                        .background(theme.accent.gradient, in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: account.displayName).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                        Text(verbatim: "@\(account.handle)").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
