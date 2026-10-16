import SwiftUI
import TimetrackCore
import TimetrackStores

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingServerChange = false

    var body: some View {
        Form {
            Section("settings.server") {
                LabeledContent("settings.server_url") {
                    Text(model.serverURL?.absoluteString ?? "–").textSelection(.enabled)
                }
                if let account = model.account {
                    LabeledContent("settings.account") { Text("\(account.displayName) (\(account.handle))") }
                }
                if let workModel = model.workModel {
                    LabeledContent("settings.timezone") { Text(workModel.timeZone.identifier) }
                }
            }
            Section {
                ForEach(ModuleKey.all, id: \.self) { key in
                    LabeledContent(moduleTitle(key)) {
                        Text(model.isEnabled(key) ? "settings.module.on" : "settings.module.off")
                            .foregroundStyle(model.isEnabled(key) ? .green : .secondary)
                    }
                }
            } header: {
                Text("settings.modules")
            } footer: {
                Text("settings.modules.hint")
            }
            Section {
                Button("account.sign_out") { Task { await model.signOut() } }
                    .accessibilityIdentifier("settings.sign_out")
                Button("settings.change_server", role: .destructive) { confirmingServerChange = true }
            }
            Section("settings.about") {
                LabeledContent("settings.version") { Text(verbatim: Self.versionText) }
                LabeledContent("settings.license") { Text(verbatim: "AGPL-3.0-only") }
            }
        }
        .navigationTitle("sidebar.settings")
        .confirmationDialog("settings.change_server.confirm", isPresented: $confirmingServerChange, titleVisibility: .visible) {
            Button("settings.change_server", role: .destructive) { Task { await model.forgetServer() } }
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
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
