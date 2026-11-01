import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Settings window (⌘,). SET-A: sidebar with the same groups, names and descriptions as the web app (SettingsStructure in the core
/// package); the detail column shows the overview (all groups with descriptions) or the selected page.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Selection? = .overview
    @State private var query = ""

    enum Selection: Hashable {
        case overview
        case entry(SettingsEntryID)
    }

    private var groups: [SettingsGroup] {
        SettingsStructure.groups(platform: .macOS, isEnabled: { model.isEnabled($0) }, query: query)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Übersicht", systemImage: "list.bullet").tag(Selection.overview)
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.entries) { entry in
                            Label(entry.title, systemImage: entry.symbol).tag(Selection.entry(entry.id))
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Einstellung suchen …")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            switch selection ?? .overview {
            case .overview: overview
            case .entry(let id): NavigationStack { destination(id) }.id(id)
            }
        }
        .frame(width: 860, height: 620)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Einstellungen").font(.title2.weight(.bold)).foregroundStyle(TT.textPrimary)
                    Text("Alle Einstellungen nach Themen geordnet. Nutze die Suche, um direkt zu einer Seite zu springen.")
                        .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
                SettingsGroupsView(groups: groups) { entry in
                    Button { selection = .entry(entry.id) } label: { SettingsEntryLabel(entry: entry) }
                        .buttonStyle(.plain).accessibilityIdentifier(entry.id.accessibilityID)
                }
                HStack {
                    Button { Task { await model.signOut() } } label: { Label("account.sign_out", systemImage: "rectangle.portrait.and.arrow.right") }
                        .disabled(model.phase == .signedOut)
                    Spacer()
                    Button("settings.change_server", role: .destructive) { Task { await model.forgetServer() } }
                }
            }
            .padding(TT.Space.xl)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
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
        case .places: MacAutomationSettingsView()
        case .triggerLinks: TriggerLinksPage() // AUD3-A
        case .notifications: PushSettingsPage()
        case .calendarFeeds: CalendarFeedsPage()
        case .deviceCalendar: CalendarSettingsView()
        case .appearance: AppearanceSettingsView()
        case .modules: ModulesSettingsView()
        case .menuBar: MenuBarSettingsView()
        case .activity: ActivitySettingsView()
        case .about: AboutSettingsView()
        case .vacationEntitlement, .vacationReminders, .overworkHints, .focusFilter, .export, .cancelled, .appleWatch: EmptyView()
        }
    }
}

private struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            AppearanceSettingsPage(sync: model.appearance) {
                FormSection("appearance.icon") {
                    // The Dock icon of a Mac app cannot be switched at runtime; it follows the default icon.
                    Label("appearance.icon.mac", systemImage: "info.circle")
                        .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        .padding(TT.Space.l).frame(maxWidth: .infinity, alignment: .leading)
                }
                FormSection(LocalizedStringKey(AD.s("settings.feedback"))) { HapticsToggle().padding(TT.Space.l) } // moved here from the old "Arbeit" tab
            }
            .padding(TT.Space.xl)
        }
        .ttScreenBackground()
    }
}

private struct ModulesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("settings.server") {
                LabeledContent("settings.server_url") { Text(model.serverURL?.absoluteString ?? "–").textSelection(.enabled).lineLimit(1).truncationMode(.middle) }
                if let workModel = model.workModel {
                    LabeledContent("settings.timezone") { Text(workModel.timeZone.identifier) }
                }
            }
            Section {
                ForEach(ModuleKey.all, id: \.self) { key in
                    LabeledContent(moduleTitle(key)) {
                        StatusChip(model.isEnabled(key) ? "settings.module.on" : "settings.module.off", tone: model.isEnabled(key) ? .success : .neutral)
                    }
                }
            } header: { Text("settings.modules") } footer: { Text("settings.modules.hint") }
        }
        .formStyle(.grouped)
    }

    private func moduleTitle(_ key: ModuleKey) -> LocalizedStringKey {
        switch key {
        case .reports: "module.reports"
        case .planning: "module.planning"
        case .transfer: "module.transfer"
        case .automation: "module.automation"
        case .mcp: "module.mcp"
        default: "module.unknown"
        }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            AboutSection(build: AppBuildInfo(platform: "macOS")) // N1b
                .padding(TT.Space.xl)
        }
        .ttScreenBackground()
    }
}
