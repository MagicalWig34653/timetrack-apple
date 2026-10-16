import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let store = model.today {
                TodayContent(store: store)
            } else {
                ScrollView { SkeletonList(rows: 3).padding(TT.Space.xl) }.ttScreenBackground()
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
            VStack(alignment: .leading, spacing: TT.Space.l) {
                Eyebrow(verbatim: dateLine).padding(.horizontal, TT.Space.xs)
                if let error = store.error { ErrorBannerView(error: error) { Task { await store.load() } } }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: TT.Space.xl) {
                        VStack(spacing: TT.Space.l) {
                            TimerCard(store: store)
                            DayStats(store: store)
                        }
                        .frame(width: 400)
                        VStack(alignment: .leading, spacing: TT.Space.l) {
                            hints
                            TodaySegments(store: store, zone: model.dayCalendar.timeZone)
                        }
                        .frame(minWidth: 320)
                    }
                    .frame(minWidth: 780)
                    VStack(alignment: .leading, spacing: TT.Space.l) {
                        TimerCard(store: store)
                        DayStats(store: store)
                        hints
                        TodaySegments(store: store, zone: model.dayCalendar.timeZone)
                    }
                }
            }
            .padding(TT.Space.xl)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .task { await store.load() }
        .refreshable { await store.load() }
        .sensoryFeedback(trigger: store.running?.id) { old, new in
            guard old != new else { return nil }
            return new != nil ? .start : .stop
        }
        .animation(.smooth(duration: 0.35), value: store.running?.id)
        .toolbar {
            ToolbarItem {
                Button { Task { await store.load() } } label: { Label("command.reload", systemImage: "arrow.clockwise") }
                    .help(Text("command.reload"))
            }
        }
    }

    @ViewBuilder private var hints: some View {
        if let hints = store.day?.breakHints, !hints.isEmpty {
            VStack(spacing: TT.Space.s) {
                ForEach(hints, id: \.code) { HintBanner(breakHintKey($0.code), symbol: "cup.and.saucer.fill") }
            }
        }
    }

    private var dateLine: String {
        Date.now.formatted(Date.FormatStyle(timeZone: model.dayCalendar.timeZone).weekday(.wide).day().month(.wide))
    }
}

private struct TimerCard: View {
    let store: TodayStore
    @AppStorage("mac.lastKind") private var lastKindRaw = SegmentKind.work.rawValue

    private var kind: Binding<SegmentKind> {
        Binding(get: { SegmentKind(rawValue: lastKindRaw).flatMap { SegmentKind.selectable.contains($0) ? $0 : nil } ?? .work },
                set: { lastKindRaw = $0.rawValue })
    }

    var body: some View {
        TimerHero(startedAt: store.running?.startedAt, kind: store.running?.kind ?? kind.wrappedValue,
                  idleTitle: "today.not_running", idleSubtitle: "today.idle_hint", runningCaption: "today.running") {
            if store.running != nil {
                Button { Task { await store.stop() } } label: { Label("today.stop", systemImage: "stop.fill") }
                    .buttonStyle(.ttDanger).controlSize(.large)
                    .accessibilityIdentifier("today.stop")
            } else {
                KindSelector(selection: kind)
                Button { Task { await store.start(kind: kind.wrappedValue) } } label: { Label("today.start", systemImage: "play.fill") }
                    .buttonStyle(.ttPrimary).controlSize(.large)
                    .accessibilityIdentifier("today.start")
            }
        }
    }
}

private struct DayStats: View {
    let store: TodayStore

    var body: some View {
        let day = store.day
        let done = (day?.evaluatedWorkSeconds ?? 0) + (day?.creditSeconds ?? 0)
        let target = day?.targetSeconds ?? 0
        let progress = target > 0 ? Double(done) / Double(target) : 0
        VStack(spacing: TT.Space.m) {
            Card {
                HStack(spacing: TT.Space.xl) {
                    ProgressRing(progress: progress, lineWidth: 12) {
                        Text(verbatim: target > 0 ? "\(Int((progress * 100).rounded())) %" : "–").font(TTFont.statSmall).foregroundStyle(TT.textPrimary)
                    }
                    .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: TT.Space.xs) {
                        Text("today.done").font(TTFont.label).foregroundStyle(TT.textSecondary)
                        Text(verbatim: DurationFormat.hoursMinutes(done))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(TT.textPrimary)
                        Text("today.of_target \(DurationFormat.hoursMinutes(target))").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        // One "vorläufig" indicator for the whole screen (day or balance); the tiles below stay quiet.
                        if day?.provisional == true || store.account?.provisional == true { StatusChip("common.provisional", tone: .neutral).padding(.top, 2) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: TT.Space.m) {
                StatTile("today.delta", value: DurationFormat.signed(day?.deltaSeconds ?? 0), tone: deltaTone(day?.deltaSeconds ?? 0), symbol: "plusminus")
                StatTile("today.balance", value: DurationFormat.signed(store.account?.balanceSeconds ?? 0), symbol: "clock.arrow.circlepath")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TodaySegments: View {
    let store: TodayStore
    let zone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            SectionHeader("today.segments") { if !store.segments.isEmpty { Text(verbatim: "\(store.segments.count)") } }
            if store.segments.isEmpty {
                Card { EmptyState(symbol: "tray", title: "today.no_segments", message: "today.no_segments.hint") }
            } else {
                ListCard { ForEach(store.segments) { SegmentRow(segment: $0, zone: zone) } }
            }
        }
    }
}
