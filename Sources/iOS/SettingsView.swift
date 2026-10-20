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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var confirmingServerChange = false
    @State private var watchStatus: WatchHandoffResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                AccountCard()
                appearanceGroup
                workGroup
                devicesGroup
                technicalGroup
                sessionActions
            }
            .settingsPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("sidebar.settings")
        .confirmationDialog("settings.change_server.confirm", isPresented: $confirmingServerChange, titleVisibility: .visible) {
            Button("settings.change_server", role: .destructive) { Task { await model.forgetServer() } }
        }
        .ttHaptic(.confirmDestructive, whenBecomesTrue: confirmingServerChange)
    }

    // MARK: - Groups (S2). Each group is a small computed property so later rows (for example vacation reminders) slot in as one line.

    /// Look of the app: accent, scheme, glow, app icon, haptics (the haptic level lives on that page).
    private var appearanceGroup: some View {
        FormSection {
            SettingsLinkRow(title: "settings.appearance", symbol: "paintpalette", id: "settings.appearance") { AppearanceView() }
        }
    }

    /// Work and planning: work model versions, vacation entitlement. (UX3: reminders and automation moved to "Mehr".)
    private var workGroup: some View {
        FormSection("Arbeit") {
            SettingsLinkRow(title: "workmodel.title", symbol: "calendar.badge.clock", id: "settings.workmodel") { WorkModelsScreen() }
            if model.isEnabled(.planning) {
                VacationEntitlementRow()
            }
        }
    }

    @ViewBuilder private var devicesGroup: some View {
        if let watchSender {
            FormSection("settings.watch", footer: "settings.watch.hint") {
                SettingsActionRow(title: "settings.watch.send", symbol: "applewatch", trailingSymbol: "arrow.up.circle", id: "settings.watch.send") {
                    Task { watchStatus = await watchSender.sendNow() }
                }
                if let watchStatus {
                    HStack {
                        StatusChip(Self.statusKey(watchStatus), tone: watchStatus == .sent ? .success : .neutral, symbol: Self.statusSymbol(watchStatus))
                        Spacer()
                    }
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .accessibilityIdentifier("settings.watch.status")
                }
            }
        }
    }

    /// Technical facts live at the bottom, one level down.
    private var technicalGroup: some View {
        FormSection("Info") {
            SettingsLinkRow(title: "Server und Module", symbol: "server.rack", id: "settings.server") { ServerModulesView() }
            SettingsLinkRow(title: "settings.about", symbol: "info.circle", value: AppBuildInfo(platform: "iOS").display, id: "settings.about") { AboutView() }
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
