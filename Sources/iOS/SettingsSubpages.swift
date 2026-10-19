import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// "Server und Module": technical read-only facts (server address, time zone, module states).
struct ServerModulesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                FormSection("settings.server") {
                    FormRow("settings.server_url", stacked: true) { Text(model.serverURL?.absoluteString ?? "–").textSelection(.enabled) }
                    if let workModel = model.workModel {
                        FormRow("settings.timezone") { Text(workModel.timeZone.identifier) }
                    }
                }
                FormSection("settings.modules", footer: "settings.modules.hint") {
                    ForEach(ModuleKey.all, id: \.self) { key in
                        FormRow(Self.title(key)) {
                            StatusChip(model.isEnabled(key) ? "settings.module.on" : "settings.module.off", tone: model.isEnabled(key) ? .success : .neutral)
                        }
                    }
                }
            }
            .settingsPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("Server und Module")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func title(_ key: ModuleKey) -> LocalizedStringKey {
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

/// "Über Timetrack": versions, licence and the support line (loads the server info when opened).
struct AboutView: View {
    var body: some View {
        ScrollView {
            AboutSection(build: AppBuildInfo(platform: "iOS")).settingsPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("settings.about")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Vacation entitlement, region, carry-over and balance entries: the sheet that used to hang off the "Urlaub" tab.
struct VacationEntitlementRow: View {
    @Environment(AppModel.self) private var model
    @State private var showing = false

    var body: some View {
        if let store = model.planning {
            SettingsActionRow(title: "Urlaubsanspruch", symbol: "beach.umbrella", id: "settings.vacation") {
                // Load before presenting: saving the sheet writes all fields, so it must start from the server values.
                Task { await store.load(); await store.loadSettings(); showing = true }
            }
            .sheet(isPresented: $showing) { VacationSettingsSheet(store: store) }
        }
    }
}

extension View {
    /// Shared width and padding of the settings pages.
    func settingsPageLayout() -> some View {
        padding(.horizontal, TT.Space.l)
            .padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
    }
}
