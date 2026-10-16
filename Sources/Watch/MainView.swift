import SwiftUI
import TimetrackCore
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
                    Text(verbatim: error.germanDescription).font(.footnote).foregroundStyle(.red)
                }
                TimerSection(store: store)
                SummarySection(store: store)
                SegmentsSection(store: store, zone: model.dayCalendar.timeZone)
            }
        }
        .navigationTitle("sidebar.today")
        .task { await store.load() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await store.load() } } }
        // 401 while in use: the session ended; ask for a new hand-over instead of showing a raw error.
        .onChange(of: store.error) {
            if store.error?.isUnauthorized == true { Task { await model.discardSessionLocally() } }
        }
    }
}

private struct TimerSection: View {
    let store: TodayStore

    var body: some View {
        VStack(spacing: 6) {
            if let running = store.running {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let clock = RunningTimerDisplay(startedAt: running.startedAt).clock(at: context.date)
                    Text(clock)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .accessibilityLabel(Text("today.timer.accessibility \(clock)"))
                }
                Label(running.kind.titleKey, systemImage: running.kind.symbol).font(.footnote).foregroundStyle(.secondary)
                Button { Task { await store.stop() } } label: {
                    Label("today.stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("watch.stop")
            } else {
                Text("today.not_running").font(.footnote).foregroundStyle(.secondary)
                Button { Task { await store.start() } } label: {
                    Label("today.start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .tint(.green)
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
        VStack(spacing: 4) {
            row("today.done", DurationFormat.hoursMinutes(done), provisional: day?.provisional == true)
            row("today.balance", DurationFormat.signed(store.account?.balanceSeconds ?? 0), provisional: store.account?.provisional == true)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private func row(_ title: LocalizedStringKey, _ value: String, provisional: Bool) -> some View {
        HStack {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.weight(.semibold)).monospacedDigit()
            if provisional { Image(systemName: "clock").font(.caption2).foregroundStyle(.secondary).accessibilityLabel(Text("common.provisional")) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SegmentsSection: View {
    let store: TodayStore
    let zone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("today.segments").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            if store.segments.isEmpty {
                Text("today.no_segments").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(store.segments) { segment in
                    HStack {
                        Image(systemName: segment.kind.symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(segment.kind.titleKey).font(.footnote)
                            Text("\(segment.startedAt.clockText(in: zone)) – \(segment.endedAt?.clockText(in: zone) ?? "…")")
                                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let end = segment.endedAt {
                            Text(DurationFormat.hoursMinutes(Int(end.timeIntervalSince(segment.startedAt)))).font(.footnote).monospacedDigit()
                        } else {
                            Text("segment.running").font(.caption2).foregroundStyle(.green)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
