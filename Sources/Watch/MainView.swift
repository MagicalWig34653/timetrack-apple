import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

struct MainView: View {
    @Environment(AppModel.self) private var model
    let receiver: WatchHandoffReceiver

    var body: some View {
        NavigationStack {
            if let store = model.today {
                TodayScreen(store: store)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink { SettingsScreen(receiver: receiver) } label: { Image(systemName: "gearshape") }
                                .accessibilityLabel(Text("sidebar.settings"))
                                .accessibilityIdentifier("watch.settings")
                        }
                    }
            } else {
                ProgressView()
            }
        }
    }
}

/// Small, non-intrusive status line under the timer.
enum TodayStatus: Equatable {
    case none
    /// Cached content is shown, the refresh is on its way.
    case refreshing
    case offline
    case sending(Int)
    case refreshFailed
}

private struct TodayScreen: View {
    let store: TodayStore
    @Environment(AppModel.self) private var model

    private var status: TodayStatus {
        let display = store.display
        if display.pendingActions > 0 { return .sending(display.pendingActions) }
        if case .active(.offline) = model.lifecycle.state { return .offline }
        if !store.hasLoadedLive, store.error == nil { return .refreshing }
        if let error = store.error, !error.isUnauthorized { return error.isNetworkError ? .offline : .refreshFailed }
        return .none
    }

    var body: some View {
        TodayContent(display: store.display, status: status, actions: TimerActions(
            start: { kind in Task { await store.start(kind: kind) } },
            stop: { Task { await store.stop() } }
        ), zone: model.dayCalendar.timeZone)
        // The accent is part of the complication's snapshot.
        .onChange(of: model.appearance.local) { TimetrackWatchApp.publish(model) }
        // 401 while in use: the session ended; ask for a new hand-over instead of showing a raw error.
        .onChange(of: store.error) {
            if store.error?.isUnauthorized == true { Task { await model.discardSessionLocally(expired: true) } }
        }
    }
}

struct TimerActions {
    let start: (SegmentKind) -> Void
    let stop: () -> Void
}

/// The whole screen as a function of `TodayDisplay`: the same view draws cached, queued and live state.
struct TodayContent: View {
    let display: TodayDisplay
    let status: TodayStatus
    let actions: TimerActions?
    var zone: TimeZone = TimeZone(identifier: "Europe/Berlin") ?? .current

    var body: some View {
        let _ = LaunchTrace.mark(display.source == .live ? "content.live" : "content.first")
        ScrollView {
            VStack(spacing: 10) {
                TimerSection(display: display, actions: actions)
                StatusLine(status: status, updatedAt: display.updatedAt, zone: zone)
                SummarySection(display: display)
                SegmentsSection(segments: display.segments, zone: zone)
            }
        }
        .navigationTitle("sidebar.today")
    }
}

private struct StatusLine: View {
    let status: TodayStatus
    let updatedAt: Date?
    let zone: TimeZone

    var body: some View {
        switch status {
        case .none: EmptyView()
        case .refreshing:
            Label("today.status.refreshing", systemImage: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(TT.textSecondary)
        case .offline:
            Label("today.status.offline", systemImage: "wifi.slash").font(.caption2).foregroundStyle(TT.textSecondary)
        case .sending(let count):
            Label("today.status.sending \(count)", systemImage: "paperplane").font(.caption2).foregroundStyle(TT.textSecondary)
                .accessibilityIdentifier("watch.sending")
        case .refreshFailed:
            Label("today.status.failed", systemImage: "exclamationmark.circle").font(.caption2).foregroundStyle(TT.textSecondary)
        }
    }
}

private struct TimerSection: View {
    let display: TodayDisplay
    let actions: TimerActions?
    /// Last chosen kind survives restarts (a non-secret preference).
    @AppStorage("watch.lastKind") private var lastKindRaw = SegmentKind.work.rawValue

    private var kind: Binding<SegmentKind> {
        Binding(
            get: { SegmentKind(rawValue: lastKindRaw).flatMap { SegmentKind.selectable.contains($0) ? $0 : nil } ?? .work },
            set: { if $0.rawValue != lastKindRaw { TTHaptics.play(.selection) }; lastKindRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            if display.isRunning, let startedAt = display.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let clock = RunningTimerDisplay(startedAt: startedAt).clock(at: context.date)
                    Text(clock)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TT.textPrimary)
                        .minimumScaleFactor(0.6)
                        .accessibilityLabel(Text("today.timer.accessibility \(clock)"))
                }
                HStack(spacing: 6) {
                    LiveDot(color: display.kind.ttTint)
                    KindBadge(display.kind)
                }
                Button { actions?.stop() } label: {
                    Label("today.stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .tint(TT.danger)
                .buttonStyle(.borderedProminent)
                .disabled(actions == nil)
                .accessibilityIdentifier("watch.stop")
            } else {
                Text("today.not_running").font(.footnote).foregroundStyle(TT.textSecondary)
                // Compact: one row that opens the system list; the choice is remembered.
                Picker("today.kind", selection: kind) {
                    ForEach(SegmentKind.selectable, id: \.self) { Label($0.titleKey, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("watch.kind")
                Button { actions?.start(kind.wrappedValue) } label: {
                    Label("today.start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .tint(Color(hex: TT.defaultAccentHex))
                .buttonStyle(.borderedProminent)
                .disabled(actions == nil)
                .accessibilityIdentifier("watch.start")
            }
        }
    }
}

private struct SummarySection: View {
    let display: TodayDisplay

    var body: some View {
        let done = display.doneSeconds
        let target = display.targetSeconds
        VStack(spacing: 6) {
            row("today.done", DurationFormat.hoursMinutes(done), provisional: display.provisional)
            if target > 0 { ProgressBar(progress: Double(done) / Double(target), height: 5) }
            if let balance = display.balanceSeconds { row("today.balance", DurationFormat.signed(balance), provisional: false) }
        }
        .padding(10)
        .background(TT.surface, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func row(_ title: LocalizedStringKey, _ value: String, provisional: Bool) -> some View {
        HStack {
            Text(title).font(.footnote).foregroundStyle(TT.textSecondary)
            Spacer()
            Text(value).font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
            if provisional { Image(systemName: "clock").font(.caption2).foregroundStyle(TT.textSecondary).accessibilityLabel(Text("common.provisional")) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Below the fold, so rows are created lazily while scrolling.
private struct SegmentsSection: View {
    let segments: [WidgetSegment]
    let zone: TimeZone

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            Text("today.segments").font(.footnote.weight(.semibold)).foregroundStyle(TT.textSecondary)
            if segments.isEmpty {
                Text("today.no_segments").font(.footnote).foregroundStyle(TT.textSecondary)
            } else {
                ForEach(segments, id: \.startedAt) { segment in
                    HStack(spacing: 8) {
                        KindGlyph(symbol: segment.kind.ttSymbol, tint: segment.kind.ttTint, size: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(segment.startedAt.clockText(in: zone)) – \(segment.endedAt?.clockText(in: zone) ?? "…")")
                                .font(.system(.footnote, design: .rounded)).monospacedDigit()
                            Text(segment.kind.titleKey).font(.caption2).foregroundStyle(segment.kind.ttTint)
                        }
                        Spacer()
                        if let end = segment.endedAt {
                            Text(DurationFormat.hoursMinutes(Int(end.timeIntervalSince(segment.startedAt)))).font(.system(.footnote, design: .rounded)).monospacedDigit()
                        } else {
                            Text("segment.running").font(.caption2).foregroundStyle(TT.success)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
