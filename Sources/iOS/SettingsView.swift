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
    @Environment(\.ttTheme) private var theme
    @State private var confirmingServerChange = false
    @State private var watchStatus: WatchHandoffResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                accountCard
                FormSection {
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        HStack {
                            Label("settings.appearance", systemImage: "paintpalette")
                                .foregroundStyle(TT.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
                        }
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.appearance")
                }
                FormSection { // N1b: work model versions (correction with preview)
                    NavigationLink {
                        WorkModelsScreen()
                    } label: {
                        HStack {
                            Label("workmodel.title", systemImage: "calendar.badge.clock").foregroundStyle(TT.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
                        }
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.workmodel")
                }
                FormSection(footer: "haptics.footer") { // N1b: plain on/off switch (grading stays on the appearance page)
                    HapticsToggle().padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                }
                FormSection { // E1: device calendars (EventKit); on this device only
                    NavigationLink {
                        CalendarSettingsView()
                    } label: {
                        HStack {
                            Label("Kalender", systemImage: "calendar").foregroundStyle(TT.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
                        }
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.calendar")
                }
                if model.isEnabled(.planning) { // R3: reminders to submit planned vacation
                    FormSection {
                        NavigationLink {
                            VacationReminderSettingsView()
                        } label: {
                            HStack {
                                Label("Urlaubserinnerungen", systemImage: "bell.badge").foregroundStyle(TT.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
                            }
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.reminders")
                    }
                }
                FormSection { // OT1: overwork notifications
                    NavigationLink {
                        OverworkSettingsView()
                    } label: {
                        HStack {
                            Label("Überstunden-Hinweise", systemImage: "clock.badge.exclamationmark").foregroundStyle(TT.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
                        }
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.overwork")
                }
                if model.isEnabled(.automation) { // L2: location automation (module `automation`)
                    FormSection {
                        NavigationLink {
                            AutomationSettingsView()
                        } label: {
                            HStack {
                                Label("Standortautomatik", systemImage: "location.circle").foregroundStyle(TT.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
                            }
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.automation")
                    }
                }
                if model.isEnabled(.automation) { // F2: hidden when the automation module is off (account or server-wide)
                    FormSection(footer: "settings.focus.hint") {
                        NavigationLink {
                            FocusFilterView()
                        } label: {
                            HStack {
                                Label("settings.focus", systemImage: "moon.circle").foregroundStyle(TT.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(TT.textTertiary)
                            }
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.focus")
                    }
                }
                FormSection("settings.server") {
                    FormRow("settings.server_url", stacked: true) { Text(model.serverURL?.absoluteString ?? "–").textSelection(.enabled) }
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
                if let watchSender {
                    FormSection("settings.watch", footer: "settings.watch.hint") {
                        Button { Task { watchStatus = await watchSender.sendNow() } } label: {
                            HStack {
                                Label("settings.watch.send", systemImage: "applewatch")
                                Spacer()
                                Image(systemName: "arrow.up.circle").foregroundStyle(TT.textTertiary)
                            }
                            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.watch.send")
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
                VStack(spacing: TT.Space.m) {
                    Button { Task { await model.signOut() } } label: { Label("account.sign_out", systemImage: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(.ttSecondary)
                        .accessibilityIdentifier("settings.sign_out")
                    Button("settings.change_server", role: .destructive) { confirmingServerChange = true }
                        .font(TTFont.label)
                        .foregroundStyle(TT.danger)
                }
                AboutSection(build: AppBuildInfo(platform: "iOS")) // N1b
            }
            .padding(.horizontal, TT.Space.l)
            .padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("sidebar.settings")
        .confirmationDialog("settings.change_server.confirm", isPresented: $confirmingServerChange, titleVisibility: .visible) {
            Button("settings.change_server", role: .destructive) { Task { await model.forgetServer() } }
        }
        .ttHaptic(.confirmDestructive, whenBecomesTrue: confirmingServerChange)
    }

    @ViewBuilder private var accountCard: some View {
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
