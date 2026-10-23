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
                            DayStandingCard(store: store)
                            QuickAbsenceRow()
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
                        DayStandingCard(store: store)
                        QuickAbsenceRow()
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
                // H5: same offer as on the iPhone (reopen the last finished entry of today; long gap asks).
                ContinueButton(store: store)
                ContinueNotice(store: store)
            }
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
