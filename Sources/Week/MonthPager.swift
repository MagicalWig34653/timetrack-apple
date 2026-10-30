#if os(iOS)
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Z2: motion of the "Zeit" screen. One spring for selection and zoom changes; a calm fade when "Reduce Motion" is on.
enum Z2Motion {
    static func spring(reduceMotion: Bool) -> Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.38, bounce: 0.18) }
}

/// U2: vertical, continuously scrolling month list (like the iOS calendar). Month sections with a sticky header, week rows of fixed
/// height, so the geometry is a pure function (`MonthListLayout`): the month at the top follows from the scroll offset and a jump is
/// an offset. Cells only read the immutable `MonthSnapshot`s of the store; the "today" mark is a circle on the number, no frame.
struct MonthList: View {
    let store: CalendarStore
    let layout: MonthListLayout
    @Binding var position: ScrollPosition
    let selected: LocalDay?
    let onVisibleMonth: (MonthKey) -> Void
    let onTap: (LocalDay) -> Void
    let onLongPress: (LocalDay) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let capacity = layout.rowHeight >= 100 ? 3 : 2
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(layout.keys) { key in
                    let snapshot = store.snapshot(for: key)
                    Section {
                        ForEach(snapshot.monthRows, id: \.cells[0].day) { row in
                            MonthWeekRow(week: row.week, cells: row.cells, today: store.today, selected: store.isRangeMode ? nil : selected,
                                         range: rangeBounds, rowHeight: layout.rowHeight, capacity: capacity, onTap: onTap, onLongPress: onLongPress)
                                .equatable()
                        }
                    } header: {
                        MonthSectionHeader(key: key, calendar: store.calendar, height: layout.headerHeight)
                    }
                }
            }
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Double.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            onVisibleMonth(layout.visibleKey(atOffset: offset))
        }
        .accessibilityIdentifier("month.list")
    }

    private var rangeBounds: ClosedRange<LocalDay>? {
        guard store.isRangeMode, let range = store.chosenRange else { return nil }
        return range.start...max(range.start, range.end)
    }
}

struct MonthSectionHeader: View {
    let key: MonthKey
    let calendar: DayCalendar
    let height: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: PlanFormat.monthName(key.month, calendar: calendar)).font(.system(.title3, weight: .bold)).foregroundStyle(TT.textPrimary)
            Text(verbatim: String(key.year)).font(.system(.title3)).foregroundStyle(Color.accentColor)
            Spacer()
        }
        .padding(.horizontal, TT.Space.l)
        .frame(height: height).frame(maxWidth: .infinity)
        .background(.bar)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One week row: ISO week number in front and seven day cells.
struct MonthWeekRow: View, Equatable {
    let week: Int
    let cells: [MonthCell]
    let today: LocalDay
    let selected: LocalDay?
    let range: ClosedRange<LocalDay>?
    let rowHeight: CGFloat
    let capacity: Int
    let onTap: (LocalDay) -> Void
    let onLongPress: (LocalDay) -> Void

    private var selectedInRow: LocalDay? { selected.flatMap { day in cells.contains { $0.day == day } ? day : nil } }

    nonisolated static func == (l: MonthWeekRow, r: MonthWeekRow) -> Bool {
        l.week == r.week && l.cells == r.cells && l.today == r.today && l.range == r.range && l.rowHeight == r.rowHeight
            && l.capacity == r.capacity && l.selectedInRow == r.selectedInRow
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: String(week)).font(.caption2).foregroundStyle(TT.textTertiary).frame(width: 26)
                .accessibilityLabel(Text("calendar.week_label \(week)"))
            ForEach(cells) { cell in
                MonthDayCell(cell: cell, isToday: cell.day == today, selected: cell.day == selected, inRange: range?.contains(cell.day) ?? false, capacity: capacity)
                    .contentShape(.rect)
                    .onTapGesture { onTap(cell.day) }
                    .onLongPressGesture(minimumDuration: 0.45) { onLongPress(cell.day) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("day.\(cell.day)")
                    .accessibilityAction(named: Text("plan.action.range")) { onLongPress(cell.day) }
            }
        }
        .frame(height: rowHeight)
        .overlay(alignment: .top) { Divider().overlay(TT.textTertiary.opacity(0.25)) }
    }
}

/// One day: number (today = filled accent circle, selected = dark circle), worked dot and up to two/three simple pills.
struct MonthDayCell: View {
    let cell: MonthCell
    let isToday: Bool
    let selected: Bool
    let inRange: Bool
    let capacity: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                number
                if cell.workedSeconds > 0 { Circle().fill(TT.success).frame(width: 5, height: 5).accessibilityHidden(true) }
            }
            .padding(.top, 4)
            pills
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 1)
        .background(inRange ? Color.accentColor.opacity(0.22) : .clear, in: .rect(cornerRadius: 8))
        .opacity(cell.inMonth ? 1 : 0)
        .allowsHitTesting(cell.inMonth)
        .accessibilityHidden(!cell.inMonth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var number: some View {
        let text = Text(verbatim: String(cell.dayNumber))
            .font(.system(.callout, weight: isToday || selected ? .semibold : .regular)).monospacedDigit()
            .frame(width: 28, height: 28)
        if isToday {
            text.foregroundStyle(Color.white).background(Circle().fill(Color.accentColor))
        } else if selected {
            text.foregroundStyle(scheme == .dark ? Color.black : Color.white).background(Circle().fill(TT.textPrimary))
        } else {
            text.foregroundStyle(cell.isHoliday ? TT.kindHoliday : (cell.isWeekend ? TT.textSecondary : TT.textPrimary))
        }
    }

    @ViewBuilder private var pills: some View {
        let split = MonthPill.visible(cell.pills, capacity: capacity)
        VStack(spacing: 2) {
            ForEach(Array(split.shown.enumerated()), id: \.offset) { _, pill in MonthPillView(pill: pill) }
            if split.hidden > 0 {
                Text(verbatim: "+\(split.hidden)").font(.system(size: 10, weight: .semibold)).foregroundStyle(TT.textSecondary).frame(height: 14)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private var label: String {
        var parts = [MonthCellLabel.longDay(cell.day)]
        if isToday { parts.append(String(localized: "time.today")) }
        parts += cell.info.holidays.map(\.displayName)
        parts += cell.info.schoolHolidays.map(\.name)
        parts += cell.info.absences.map { "\($0.kind.plainName), \($0.status.plainName)" }
        if let plan = cell.info.plan { parts.append(String(localized: "calendar.plan_label \(plan.mode.plainName)")) }
        if cell.workedSeconds > 0 { parts.append("erfasst \(DurationFormat.hoursMinutes(cell.workedSeconds))") }
        return parts.joined(separator: ", ")
    }
}

/// A simple coloured pill with a short text; planned/requested absences are outlined instead of filled.
struct MonthPillView: View {
    let pill: MonthPill

    var body: some View {
        let tint = pill.kind.tint
        Text(verbatim: pill.title)
            .font(.system(size: 10, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            .foregroundStyle(pill.tentative ? tint : Color.white)
            .padding(.horizontal, 4).frame(maxWidth: .infinity).frame(height: 14)
            .background { if pill.tentative { RoundedRectangle(cornerRadius: 4).strokeBorder(tint, lineWidth: 1) } else { RoundedRectangle(cornerRadius: 4).fill(tint) } }
            .padding(.horizontal, 1)
    }
}

extension MonthPill {
    var title: String {
        switch kind {
        case .holiday: text ?? "Feiertag"
        case .absence(let kind): kind.plainName
        case .plan(let mode): mode.plainName
        }
    }
}

extension MonthPill.Kind {
    var tint: Color {
        switch self {
        case .holiday: TT.kindHoliday
        case .absence(let kind): kind.ttTint
        case .plan(let mode): mode.tint
        }
    }
}

enum MonthCellLabel {}

extension MonthCellLabel {
    /// "Montag, 20. Oktober": a calendar date has no time zone, so the label is formatted in UTC from the day string.
    static func longDay(_ day: LocalDay) -> String {
        guard let p = LocalDays.parse(day) else { return day }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        guard let date = utc.date(from: DateComponents(year: p.year, month: p.month, day: p.day, hour: 12)) else { return day }
        return date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.wide).day().month(.wide))
    }
}

extension MonthMarker {
    var tint: Color {
        switch self {
        case .absence(let kind): kind.ttTint
        case .holiday: TT.kindHoliday
        case .plan(let mode): mode.tint
        }
    }
}
#endif
