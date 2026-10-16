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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = store.error {
                    HStack {
                        error.messageText
                        Spacer()
                        Button("common.retry") { Task { await store.load() } }
                    }
                    .padding(12)
                    .background(.red.opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("today.error")
                }
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
                SegmentsSection(segments: store.segments)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .toolbar {
            ToolbarItem {
                Button { Task { await store.load() } } label: { Label("command.reload", systemImage: "arrow.clockwise") }
                    .help(Text("command.reload"))
            }
        }
    }
}

private struct TimerCard: View {
    let store: TodayStore
    @State private var kind: SegmentKind = .work

    var body: some View {
        VStack(spacing: 14) {
            if let running = store.running {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(RunningTimerDisplay(startedAt: running.startedAt).clock(at: context.date))
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel(Text("today.timer.accessibility \(RunningTimerDisplay(startedAt: running.startedAt).clock(at: context.date))"))
                }
                Label(running.kind.titleKey, systemImage: running.kind.symbol).foregroundStyle(.secondary)
                Button { Task { await store.stop() } } label: {
                    Label("today.stop", systemImage: "stop.fill").frame(minWidth: 160)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(.red)
                .accessibilityIdentifier("today.stop")
            } else {
                Text("today.not_running").font(.title2).foregroundStyle(.secondary)
                HStack {
                    Picker("today.kind", selection: $kind) {
                        ForEach(SegmentKind.selectable, id: \.self) { Text($0.titleKey).tag($0) }
                    }
                    .frame(maxWidth: 170)
                    Button { Task { await store.start(kind: kind) } } label: {
                        Label("today.start", systemImage: "play.fill").frame(minWidth: 140)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("today.start")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(in: .rect(cornerRadius: 24))
    }
}

private struct SummaryGrid: View {
    let store: TodayStore

    var body: some View {
        let day = store.day
        let done = (day?.evaluatedWorkSeconds ?? 0) + (day?.creditSeconds ?? 0)
        HStack(spacing: 12) {
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

private struct SegmentsSection: View {
    let segments: [Segment]
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("today.segments").font(.headline)
            if segments.isEmpty {
                Text("today.no_segments").foregroundStyle(.secondary)
            } else {
                ForEach(segments) { SegmentRow(segment: $0, zone: model.dayCalendar.timeZone) }
            }
        }
    }
}

struct SegmentRow: View {
    let segment: Segment
    let zone: TimeZone

    var body: some View {
        HStack {
            Image(systemName: segment.kind.symbol).frame(width: 22).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(segment.kind.titleKey)
            Spacer()
            if let end = segment.endedAt {
                Text("\(segment.startedAt.clockText(in: zone)) – \(end.clockText(in: zone))").monospacedDigit()
                Text(DurationFormat.hoursMinutes(Int(end.timeIntervalSince(segment.startedAt))))
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
            } else {
                Text("\(segment.startedAt.clockText(in: zone)) – …").monospacedDigit()
                Text("segment.running").foregroundStyle(.green)
            }
            if segment.needsReview {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    .accessibilityLabel(Text("segment.needs_review"))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
