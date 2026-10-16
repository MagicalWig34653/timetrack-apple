import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let account = model.account {
                    Card {
                        HStack(spacing: TT.Space.l) {
                            Text(verbatim: String(account.displayName.prefix(1)).uppercased())
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(LinearGradient(colors: [Color(hex: 0x3B82F6), Color(hex: 0x1D4ED8)], startPoint: .top, endPoint: .bottom), in: .circle)
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
                FormSection("settings.server") {
                    FormRow("settings.server_url") { Text(model.serverURL?.absoluteString ?? "–").textSelection(.enabled).lineLimit(1).truncationMode(.middle) }
                    if let workModel = model.workModel {
                        FormRow("settings.timezone") { Text(workModel.timeZone.identifier) }
                    }
                }
                FormSection("settings.modules", footer: "settings.modules.hint") {
                    ForEach(ModuleKey.all, id: \.self) { key in
                        FormRow(moduleTitle(key)) {
                            StatusChip(model.isEnabled(key) ? "settings.module.on" : "settings.module.off", tone: model.isEnabled(key) ? .success : .neutral)
                        }
                    }
                }
                HStack(spacing: TT.Space.m) {
                    Button { Task { await model.signOut() } } label: { Label("account.sign_out", systemImage: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(.ttSecondary)
                        .disabled(model.phase == .signedOut)
                    Button("settings.change_server", role: .destructive) { Task { await model.forgetServer() } }
                        .foregroundStyle(TT.danger)
                }
                FormSection("settings.about") {
                    FormRow("settings.version") { Text(verbatim: Self.versionText).monospacedDigit() }
                    FormRow("settings.license") { Text(verbatim: "AGPL-3.0-only") }
                }
            }
            .padding(TT.Space.xl)
        }
        .ttScreenBackground()
        .frame(width: 520, height: 640)
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
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
