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
                ScrollView { SkeletonList(rows: 3).padding(TT.Space.l) }.ttScreenBackground()
            }
        }
        .navigationTitle("sidebar.today")
    }
}

private struct TodayContent: View {
    let store: TodayStore
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Width of the content area; the two-column layout needs room beyond the size class (iPad portrait with an open sidebar is narrow).
    @State private var contentWidth: CGFloat = 0
    private var twoColumns: Bool { sizeClass == .regular && contentWidth >= 760 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                Eyebrow(verbatim: dateLine).padding(.horizontal, TT.Space.xs)
                if let error = store.error { ErrorBannerView(error: error) { Task { await store.load() } } }
                if twoColumns {
                    HStack(alignment: .top, spacing: TT.Space.xl) {
                        VStack(spacing: TT.Space.l) {
                            TimerCard(store: store)
                            DayStandingCard(store: store)
                            QuickAbsenceRow()
                        }
                        .frame(maxWidth: 440)
                        VStack(alignment: .leading, spacing: TT.Space.l) {
                            hints
                            TodaySegments(store: store, zone: model.dayCalendar.timeZone)
                        }
                    }
                } else {
                    TimerCard(store: store)
                    DayStandingCard(store: store)
                    QuickAbsenceRow()
                    hints
                    TodaySegments(store: store, zone: model.dayCalendar.timeZone)
                }
            }
            .padding(.horizontal, TT.Space.l)
            .padding(.vertical, TT.Space.s)
            .frame(maxWidth: twoColumns ? 1100 : TT.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .ttScreenBackground()
        .task { await store.load() }
        .refreshable { await store.load(); TTHaptics.play(.softTap) }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await store.load() } } }
        .animation(.smooth(duration: 0.35), value: store.running?.id)
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
    /// H2: on iPhone (compact) the "Jetzt" bar above the tab bar is the single start/stop control on every tab,
    /// including Heute. Where the bar is absent (iPad sidebar layout, regular width) the card keeps its own button.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("ios.lastKind") private var lastKindRaw = SegmentKind.work.rawValue

    private var cardHasButton: Bool { sizeClass == .regular }

    private var kind: Binding<SegmentKind> {
        Binding(get: { SegmentKind(rawValue: lastKindRaw).flatMap { SegmentKind.selectable.contains($0) ? $0 : nil } ?? .work },
                set: { lastKindRaw = $0.rawValue })
    }

    var body: some View {
        TimerHero(startedAt: store.running?.startedAt, kind: store.running?.kind ?? kind.wrappedValue,
                  idleTitle: "today.not_running", idleSubtitle: "today.idle_hint", runningCaption: "today.running") {
            if store.running != nil {
                if cardHasButton {
                    Button { Task { await store.stop() } } label: {
                        Label("today.stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.ttDanger)
                    .controlSize(.large)
                    .accessibilityIdentifier("today.stop")
                }
            } else {
                // The kind choice stays on the card; the bar's start uses the same stored choice ("ios.lastKind").
                KindSelector(selection: kind)
                if cardHasButton {
                    Button { Task { await store.start(kind: kind.wrappedValue) } } label: {
                        Label("today.start", systemImage: "play.fill")
                    }
                    .buttonStyle(.ttPrimary)
                    .controlSize(.large)
                    .accessibilityIdentifier("today.start")
                }
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
                ListCard {
                    ForEach(store.segments) { SegmentRow(segment: $0, zone: zone) }
                }
            }
        }
    }
}
