import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Settings window: general (account, server, modules) and appearance (accent colour, light/dark, icon note).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("settings.general", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("settings.appearance", systemImage: "paintpalette") }
        }
        .frame(width: 520, height: 700)
    }
}

private struct AppearanceSettingsView: View {
    var body: some View {
        ScrollView {
            AppearanceSettingsPage {
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
    @Environment(\.ttTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let account = model.account {
                    Card {
                        HStack(spacing: TT.Space.l) {
                            Text(verbatim: String(account.displayName.prefix(1)).uppercased())
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                                .foregroundStyle(theme.onAccent)
                                .frame(width: 52, height: 52)
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
