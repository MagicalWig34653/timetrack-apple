import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// H3: views for the expected end of the day, the break status and today's mini timeline. Used on "Heute" and in the "Jetzt" sheet.
// Numbers come from `DayOutlook` (pure rules in the core); nothing here books or invents time.

/// One calm line with a symbol: "Feierabend etwa 14:42", "Pause in 3:45 fällig".
struct OutlookLine: View {
    let symbol: String
    let text: Text
    var tone: Color = TT.textSecondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TT.Space.s) {
            Image(systemName: symbol).imageScale(.small).foregroundStyle(tone).frame(width: 18).accessibilityHidden(true)
            text.font(TTFont.meta).foregroundStyle(tone == TT.textSecondary ? TT.textSecondary : tone).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Expected end and break status of the day (only what is known; no line when there is nothing to say).
struct DayOutlookLines: View {
    let outlook: DayOutlook
    let zone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.xs) {
            switch outlook.end {
            case .planned(let date): OutlookLine(symbol: "flag.checkered", text: ux3("h3.end.planned \(clock(date))")).accessibilityIdentifier("outlook.end")
            case .estimated(let date): OutlookLine(symbol: "flag.checkered", text: ux3("h3.end.estimated \(clock(date))")).accessibilityIdentifier("outlook.end")
            case .reached, .unknown: EmptyView()
            }
            breakLine
        }
    }

    @ViewBuilder private var breakLine: some View {
        switch outlook.breakStatus {
        case .none:
            EmptyView()
        case .taken(let seconds):
            OutlookLine(symbol: "cup.and.saucer.fill", text: ux3("h3.break.taken \(DurationFormat.hoursMinutes(seconds))")).accessibilityIdentifier("outlook.break")
        case .dueIn(let seconds, let required):
            OutlookLine(symbol: "cup.and.saucer", text: ux3("h3.break.due \(DurationFormat.hoursMinutes(seconds)) \(required / 60)")).accessibilityIdentifier("outlook.break")
        case .missing(let required, let taken):
            OutlookLine(symbol: "cup.and.saucer", text: ux3("h3.break.missing \(required / 60) \(DurationFormat.hoursMinutes(taken))"), tone: TT.warning)
                .accessibilityIdentifier("outlook.break")
        }
    }

    private func clock(_ date: Date) -> String { date.formatted(Date.FormatStyle(timeZone: zone).hour().minute()) }
}

/// Today's entries as one horizontal strip from the first start to now: colour per kind, gaps stay empty (a gap is a break or simply nothing).
struct DayTimeline: View {
    let segments: [Segment]
    let running: Segment?
    let now: Date
    let zone: TimeZone
    @Environment(\.colorScheme) private var scheme

    private var entries: [Segment] { segments.filter { !$0.voided }.sorted { $0.startedAt < $1.startedAt } }

    var body: some View {
        if let first = entries.first?.startedAt {
            let end = max(now, entries.compactMap(\.endedAt).max() ?? now)
            let span = max(end.timeIntervalSince(first), 60)
            VStack(spacing: TT.Space.xs) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(TT.separator.opacity(0.5))
                        ForEach(entries) { entry in
                            let from = entry.startedAt.timeIntervalSince(first) / span
                            let to = ((entry.endedAt ?? now).timeIntervalSince(first)) / span
                            Capsule().fill(entry.kind.ttTint.opacity(scheme == .dark ? 0.85 : 0.9))
                                .frame(width: max(4, proxy.size.width * (to - from)))
                                .offset(x: proxy.size.width * from)
                        }
                    }
                }
                .frame(height: 12)
                HStack {
                    Text(first, format: Date.FormatStyle(timeZone: zone).hour().minute())
                    Spacer()
                    if running != nil { ux3("h3.timeline.now") } else { Text(end, format: Date.FormatStyle(timeZone: zone).hour().minute()) }
                }
                .font(.caption2).monospacedDigit().foregroundStyle(TT.textTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ux3String("h3.timeline.spoken \(entries.count) \(first.formatted(Date.FormatStyle(timeZone: zone).hour().minute()))")))
            .accessibilityIdentifier("sheet.timeline")
        }
    }
}

extension SegmentKind {
    /// Plain localized name for interpolation into other strings and VoiceOver labels (`ttTitle` is a key, not a string).
    var plainName: String {
        switch self {
        case .work, .unknown: String(localized: "kind.work")
        case .travel: String(localized: "kind.travel")
        case .school: String(localized: "kind.school")
        }
    }
}
