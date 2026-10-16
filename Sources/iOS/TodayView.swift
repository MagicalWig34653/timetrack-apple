import SwiftUI
import TimetrackCore
import TimetrackStores

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let store = model.today {
                TodayContent(store: store)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("sidebar.today")
    }
}

private struct TodayContent: View {
    let store: TodayStore
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = store.error { ErrorBanner(error: error) { Task { await store.load() } } }
                TimerCard(store: store)
                SummaryGrid(store: store)
                if let hints = store.day?.breakHints, !hints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(hints, id: \.code) { hint in
                            Label(breakHintKey(hint.code), systemImage: "cup.and.saucer")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("today.segments").font(.headline)
                    if store.segments.isEmpty {
                        Text("today.no_segments").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.segments) { segment in
                            SegmentRow(segment: segment, zone: model.dayCalendar.timeZone)
                            if segment.id != store.segments.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await store.load() } } }
    }
}

private struct TimerCard: View {
    let store: TodayStore
    @State private var kind: SegmentKind = .work

    var body: some View {
        VStack(spacing: 14) {
            if let running = store.running {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let clock = RunningTimerDisplay(startedAt: running.startedAt).clock(at: context.date)
                    Text(clock)
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .accessibilityLabel(Text("today.timer.accessibility \(clock)"))
                }
                Label(running.kind.titleKey, systemImage: running.kind.symbol).foregroundStyle(.secondary)
                Button { Task { await store.stop() } } label: {
                    Label("today.stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(.red)
                .accessibilityIdentifier("today.stop")
            } else {
                Text("today.not_running").font(.title3).foregroundStyle(.secondary)
                Picker("today.kind", selection: $kind) {
                    ForEach(SegmentKind.selectable, id: \.self) { Text($0.titleKey).tag($0) }
                }
                .pickerStyle(.segmented)
                Button { Task { await store.start(kind: kind) } } label: {
                    Label("today.start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityIdentifier("today.start")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassEffect(in: .rect(cornerRadius: 24))
    }
}

private struct SummaryGrid: View {
    let store: TodayStore

    var body: some View {
        let day = store.day
        let done = (day?.evaluatedWorkSeconds ?? 0) + (day?.creditSeconds ?? 0)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            tile("today.done", DurationFormat.hoursMinutes(done), provisional: day?.provisional == true)
            tile("today.target", DurationFormat.hoursMinutes(day?.targetSeconds ?? 0))
            tile("today.delta", DurationFormat.signed(day?.deltaSeconds ?? 0), provisional: day?.provisional == true)
            tile("today.balance", DurationFormat.signed(store.account?.balanceSeconds ?? 0), provisional: store.account?.provisional == true)
        }
    }

    private func tile(_ title: LocalizedStringKey, _ value: String, provisional: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(provisional ? "common.provisional" : " ").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct SegmentRow: View {
    let segment: Segment
    let zone: TimeZone

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: segment.kind.symbol).frame(width: 24).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.kind.titleKey)
                if let note = segment.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let end = segment.endedAt {
                    Text("\(segment.startedAt.clockText(in: zone)) – \(end.clockText(in: zone))").monospacedDigit().fixedSize()
                    Text(DurationFormat.hoursMinutes(Int(end.timeIntervalSince(segment.startedAt))))
                        .fixedSize()
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text("\(segment.startedAt.clockText(in: zone)) – …").monospacedDigit().fixedSize()
                    Text("segment.running").font(.caption).foregroundStyle(.green)
                }
            }
            if segment.needsReview {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    .accessibilityLabel(Text("segment.needs_review"))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
