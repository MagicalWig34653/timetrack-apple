import SwiftUI
import TimetrackCore
import TimetrackStores

struct SettingsView: View {
    @Environment(AppModel.self) private var model

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
            Section("settings.modules") {
                ForEach(ModuleKey.all, id: \.self) { key in
                    LabeledContent(moduleTitle(key)) {
                        Text(model.isEnabled(key) ? "settings.module.on" : "settings.module.off")
                            .foregroundStyle(model.isEnabled(key) ? .green : .secondary)
                    }
                }
                Text("settings.modules.hint").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("account.sign_out") { Task { await model.signOut() } }
                    .disabled(model.phase == .signedOut)
                Button("settings.change_server", role: .destructive) { Task { await model.forgetServer() } }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
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
