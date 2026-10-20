import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        switch model.phase {
        case .restoring:
            ZStack {
                TTBackdrop()
                VStack(spacing: TT.Space.l) { BrandMark(size: 72); ProgressView() }
                    .accessibilityElement(children: .ignore).accessibilityLabel(Text("root.loading"))
            }
        case .signedOut, .offline:
            SignInView()
        case .recoveryRestricted:
            RecoveryRestrictedView()
        case .signedIn:
            MainView()
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    private func items(planning: Bool) -> [SidebarItem] {
        SidebarItem.allCases.filter { $0.isPlanning == planning && ($0.requiredModule.map(model.isEnabled) ?? true) }
    }

    var body: some View {
        @Bindable var ui = ui
        NavigationSplitView {
            List(selection: $ui.selection) {
                Section(AD.s("sidebar.section.capture")) {
                    ForEach(items(planning: false)) { row($0) }
                }
                if !items(planning: true).isEmpty {
                    Section(AD.s("sidebar.section.planning")) {
                        ForEach(items(planning: true)) { row($0) }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFooter() }
        } detail: {
            switch ui.selection {
            case .today: TodayView()
            case .time: TimeView()
            case .planning: NavigationStack { PlanningHubScreen() }
            case .calendar: CalendarScreen()
            case .vacation: VacationScreen()
            }
        }
        .ttSyncStatusLine() // UX3: only while actions wait or the server is unreachable
        .toolbar { ToolbarItem(placement: .primaryAction) { TimerToolbarButton() } }
        // A module switched off while its screen is open falls back to "Heute".
        .onChange(of: model.isEnabled(.planning)) { if !model.isEnabled(.planning), ui.selection.isPlanning { ui.selection = .today } }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.titleKey, systemImage: item.symbol)
            .tag(item)
            .accessibilityIdentifier("sidebar.\(item.rawValue)")
    }
}

/// Account name and, while a segment runs, a live elapsed time at the foot of the sidebar.
private struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.xs) {
            if let running = model.today?.running {
                HStack(spacing: TT.Space.xs) {
                    Circle().fill(TT.success).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(running.startedAt, style: .timer).monospacedDigit().font(TTFont.meta).foregroundStyle(TT.textPrimary)
                }
            }
            if let account = model.account {
                HStack(spacing: TT.Space.s) {
                    Image(systemName: "person.crop.circle.fill").foregroundStyle(TT.textSecondary)
                    Text(verbatim: account.displayName).font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("account.signed_in_as \(account.displayName)"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TT.Space.m).padding(.vertical, TT.Space.s)
    }
}

/// Window toolbar button: start (last used kind) or stop, on every screen.
private struct TimerToolbarButton: View {
    @Environment(AppModel.self) private var model
    @AppStorage("mac.lastKind") private var lastKindRaw = SegmentKind.work.rawValue

    var body: some View {
        if let today = model.today {
            if today.running != nil {
                Button { Task { await today.stop() } } label: { Label("command.stop", systemImage: "stop.fill") }
                    .help(Text("command.stop")).tint(TT.danger)
            } else {
                Button {
                    let kind = SegmentKind(rawValue: lastKindRaw).flatMap { SegmentKind.selectable.contains($0) ? $0 : nil } ?? .work
                    Task { await today.start(kind: kind) }
                } label: { Label("command.start", systemImage: "play.fill") }
                    .help(Text("command.start"))
            }
        }
    }
}

struct RecoveryRestrictedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: TT.Space.l) {
            EmptyState(symbol: "key.horizontal.fill", title: "recovery.title", message: "recovery.explanation")
            if let error = model.lastError { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { model.lastError = nil } }
            Button("recovery.add_passkey") { Task { await model.addPasskey(name: Host.current().localizedName) } }
                .buttonStyle(.ttPrimary).controlSize(.large)
                .disabled(model.isBusy)
            Button("account.sign_out") { Task { await model.signOut() } }.buttonStyle(.ttSecondary)
        }
        .padding(TT.Space.xl)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ttScreenBackground()
    }
}
