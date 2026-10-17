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

private struct TodayScreen: View {
    let store: TodayStore
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let error = store.error, !error.isUnauthorized {
                    Text(verbatim: error.germanDescription).font(.footnote).foregroundStyle(TT.danger)
                }
                TimerSection(store: store)
                SummarySection(store: store)
                SegmentsSection(store: store, zone: model.dayCalendar.timeZone)
            }
        }
        .navigationTitle("sidebar.today")
        .task { await store.load() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await store.load() } } }
        // Keep the complication's non-secret snapshot in step with what this screen shows.
        .onChange(of: ComplicationState(store: store, appearance: model.appearance.local)) { publishSnapshot() }
        .task { publishSnapshot() }
        // 401 while in use: the session ended; ask for a new hand-over instead of showing a raw error.
        .onChange(of: store.error) {
            if store.error?.isUnauthorized == true { Task { await model.discardSessionLocally() } }
        }
    }
}

private extension TodayScreen {
    @MainActor func publishSnapshot() {
        let zone = model.dayCalendar
        let day = store.day
        WidgetBridge.publish(
            running: store.running,
            todaySeconds: (day?.evaluatedWorkSeconds ?? 0) + (day?.creditSeconds ?? 0),
            day: zone.day(for: .now), timeZone: zone.timeZone.identifier,
            accentHex: AppearanceKeys.effectiveHex(model.appearance.local), colorScheme: model.appearance.local.scheme
        )
    }
}

/// Equatable digest of the store values the complication shows, so `onChange` fires only when they change.
private struct ComplicationState: Equatable {
    let runningID: UUID?
    let kind: SegmentKind?
    let todaySeconds: Int
    let appearance: LocalAppearance
    @MainActor init(store: TodayStore, appearance: LocalAppearance) {
        self.appearance = appearance
        runningID = store.running?.id
        kind = store.running?.kind
        todaySeconds = (store.day?.evaluatedWorkSeconds ?? 0) + (store.day?.creditSeconds ?? 0)
    }
}

private struct TimerSection: View {
    let store: TodayStore
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
            if let running = store.running {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let clock = RunningTimerDisplay(startedAt: running.startedAt).clock(at: context.date)
                    Text(clock)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TT.textPrimary)
                        .minimumScaleFactor(0.6)
                        .accessibilityLabel(Text("today.timer.accessibility \(clock)"))
                }
                HStack(spacing: 6) {
                    LiveDot(color: running.kind.ttTint)
                    KindBadge(running.kind)
                }
                Button { Task { await store.stop() } } label: {
                    Label("today.stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .tint(TT.danger)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("watch.stop")
            } else {
                Text("today.not_running").font(.footnote).foregroundStyle(TT.textSecondary)
                // Compact: one row that opens the system list; the choice is remembered.
                Picker("today.kind", selection: kind) {
                    ForEach(SegmentKind.selectable, id: \.self) { Label($0.titleKey, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("watch.kind")
                Button { Task { await store.start(kind: kind.wrappedValue) } } label: {
                    Label("today.start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .tint(Color(hex: TT.defaultAccentHex))
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("watch.start")
            }
        }
    }
}

private struct SummarySection: View {
    let store: TodayStore

    var body: some View {
        let day = store.day
        let done = (day?.evaluatedWorkSeconds ?? 0) + (day?.creditSeconds ?? 0)
        let target = day?.targetSeconds ?? 0
        VStack(spacing: 6) {
            row("today.done", DurationFormat.hoursMinutes(done), provisional: day?.provisional == true)
            if target > 0 { ProgressBar(progress: Double(done) / Double(target), height: 5) }
            row("today.balance", DurationFormat.signed(store.account?.balanceSeconds ?? 0), provisional: store.account?.provisional == true)
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

private struct SegmentsSection: View {
    let store: TodayStore
    let zone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("today.segments").font(.footnote.weight(.semibold)).foregroundStyle(TT.textSecondary)
            if store.segments.isEmpty {
                Text("today.no_segments").font(.footnote).foregroundStyle(TT.textSecondary)
            } else {
                ForEach(store.segments) { segment in
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
