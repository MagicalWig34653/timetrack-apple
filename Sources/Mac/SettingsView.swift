import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Settings window (⌘,): native toolbar tabs General, Appearance, Work and About; grouped forms instead of card pages.
struct SettingsView: View {
    /// Debug bisect aid: `TT_DEV_TABS=m` shows only the named new tabs (m, a, t). Always on in release builds.
    private func tabOn(_ letter: String) -> Bool {
        #if DEBUG
        if let only = ProcessInfo.processInfo.environment["TT_DEV_TABS"] { return only.contains(letter) }
        #endif
        return true
    }

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("settings.general", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("settings.appearance", systemImage: "paintpalette") }
            WorkSettingsView()
                .tabItem { Label(AD.s("settings.work"), systemImage: "briefcase") }
            if tabOn("m") { MenuBarSettingsView()
                .tabItem { Label("Menüleiste", systemImage: "menubar.rectangle") } }
            if tabOn("a") { MacAutomationSettingsView()
                .tabItem { Label("Automatik", systemImage: "location.circle") } }
            if tabOn("t") { ActivitySettingsView()
                .tabItem { Label("Aktivität", systemImage: "square.stack.3d.up") } }
            CalendarSettingsView()
                .tabItem { Label("Kalender", systemImage: "calendar") }
            CalendarFeedsPage()
                .tabItem { Label("Kalenderabos", systemImage: "calendar.badge.plus") }
            PushSettingsPage()
                .tabItem { Label("Push", systemImage: "bell.badge.waveform") }
            AboutSettingsView()
                .tabItem { Label("settings.about", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 600)
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
            }
            .padding(TT.Space.xl)
        }
        .ttScreenBackground()
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            if let account = model.account {
                Section("settings.account") {
                    LabeledContent(AD.s("settings.name")) { Text(verbatim: account.displayName) }
                    LabeledContent(AD.s("settings.handle")) { Text(verbatim: "@\(account.handle)") }
                }
            }
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
            Section {
                HStack {
                    Button { Task { await model.signOut() } } label: { Label("account.sign_out", systemImage: "rectangle.portrait.and.arrow.right") }
                        .disabled(model.phase == .signedOut)
                    Spacer()
                    Button("settings.change_server", role: .destructive) { Task { await model.forgetServer() } }
                }
            }
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

private struct WorkSettingsView: View {
    @State private var showWorkModels = false
    @State private var showTimeAccount = false

    var body: some View {
        Form {
            Section {
                Button { showWorkModels = true } label: { Label("workmodel.title", systemImage: "calendar.badge.clock") }
                    .accessibilityIdentifier("settings.workmodel")
                Button { showTimeAccount = true } label: { Label(wmKey("wm.account.title"), systemImage: "plusminus.circle") } // WM2
                    .accessibilityIdentifier("settings.timeaccount")
            } footer: { Text(AD.s("settings.work.workmodel_hint")) }
            Section(AD.s("settings.feedback")) { HapticsToggle() }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showWorkModels) {
            NavigationStack { WorkModelsScreen().toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { showWorkModels = false } } } }
                .frame(minWidth: 560, minHeight: 640)
        }
        .sheet(isPresented: $showTimeAccount) {
            NavigationStack { TimeAccountScreen().toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { showTimeAccount = false } } } }
                .frame(minWidth: 560, minHeight: 640)
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
