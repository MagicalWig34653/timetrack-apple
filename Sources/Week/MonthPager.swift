import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Z2: motion of the "Zeit" screen. One spring for selection and zoom changes; a calm fade when "Reduce Motion" is on.
enum Z2Motion {
    static func spring(reduceMotion: Bool) -> Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.38, bounce: 0.18) }
}

/// Horizontal month pager (Z2). Every month is a page of a lazy paging scroll view, so the grid follows the finger instead of
/// jumping after the gesture; pages are cheap because they only read the immutable `MonthSnapshot`s that the store prefetched.
struct MonthPager: View {
    let store: CalendarStore
    @Binding var position: Int?
    let selected: LocalDay?
    let rowHeight: CGFloat
    let namespace: Namespace.ID
    let onTap: (LocalDay) -> Void
    let onLongPress: (LocalDay) -> Void

    /// ±40 years around today are reachable by swiping; the picker covers other years by jumping (the window then moves).
    private let reach = 480

    static func height(rowHeight: CGFloat) -> CGFloat { rowHeight * 6 + 6 }

    var body: some View {
        let anchor = MonthKey(day: store.today)?.index ?? 0
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach((anchor - reach)...(anchor + reach), id: \.self) { index in
                    MonthPageView(snapshot: store.snapshot(for: MonthKey(index: index)), today: store.today, selected: store.isRangeMode ? nil : selected,
                                  range: rangeBounds, rowHeight: rowHeight, namespace: namespace, onTap: onTap, onLongPress: onLongPress)
                        .containerRelativeFrame(.horizontal)
                        .accessibilityHidden(index != store.visibleKey.index)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position, anchor: .leading)
        .scrollIndicators(.hidden)
        .frame(height: Self.height(rowHeight: rowHeight))
    }

    private var rangeBounds: ClosedRange<LocalDay>? {
        guard store.isRangeMode, let range = store.chosenRange else { return nil }
        return range.start...max(range.start, range.end)
    }
}

/// One month: six fixed-height rows with the ISO week number in front, so the page never changes height between months.
struct MonthPageView: View, Equatable {
    let snapshot: MonthSnapshot
    let today: LocalDay
    let selected: LocalDay?
    let range: ClosedRange<LocalDay>?
    let rowHeight: CGFloat
    let namespace: Namespace.ID
    let onTap: (LocalDay) -> Void
    let onLongPress: (LocalDay) -> Void

    nonisolated static func == (lhs: MonthPageView, rhs: MonthPageView) -> Bool {
        lhs.snapshot == rhs.snapshot && lhs.today == rhs.today && lhs.selected == rhs.selected && lhs.range == rhs.range && lhs.rowHeight == rhs.rowHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                Divider().overlay(TT.textTertiary.opacity(0.25))
                HStack(spacing: 0) {
                    Text(verbatim: snapshot.weekNumbers.indices.contains(row) ? String(snapshot.weekNumbers[row]) : "")
                        .font(.caption2).foregroundStyle(TT.textTertiary).frame(width: 26)
                        .accessibilityLabel(Text("calendar.week_label \(snapshot.weekNumbers.indices.contains(row) ? snapshot.weekNumbers[row] : 0)"))
                    ForEach(0..<7, id: \.self) { column in
                        let cell = snapshot.cells[row * 7 + column]
                        MonthDayCell(cell: cell, isToday: cell.day == today, selected: cell.day == selected, inRange: range?.contains(cell.day) ?? false,
                                     rowHeight: rowHeight, namespace: namespace)
                            .equatable()
                            .onTapGesture { onTap(cell.day) }
                            .onLongPressGesture(minimumDuration: 0.45) { onLongPress(cell.day) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("day.\(cell.day)")
                            .accessibilityAction(named: Text("plan.action.range")) { onLongPress(cell.day) }
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }
}

/// One day of the grid: number (today = accent circle, selection = inverted circle that glides between days) and up to three dots.
struct MonthDayCell: View, Equatable {
    let cell: MonthCell
    let isToday: Bool
    let selected: Bool
    let inRange: Bool
    let rowHeight: CGFloat
    let namespace: Namespace.ID
    @Environment(\.colorScheme) private var scheme

    nonisolated static func == (lhs: MonthDayCell, rhs: MonthDayCell) -> Bool {
        lhs.cell == rhs.cell && lhs.isToday == rhs.isToday && lhs.selected == rhs.selected && lhs.inRange == rhs.inRange && lhs.rowHeight == rhs.rowHeight
    }

    var body: some View {
        VStack(spacing: 3) {
            number
            HStack(spacing: 3) {
                ForEach(Array(cell.markers.enumerated()), id: \.offset) { _, marker in Circle().fill(marker.tint).frame(width: 6, height: 6) }
            }
            .frame(height: 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(inRange ? Color.accentColor.opacity(0.22) : .clear, in: .rect(cornerRadius: 10))
        .opacity(cell.inMonth ? 1 : 0.5)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var number: some View {
        let text = Text(verbatim: String(cell.dayNumber))
            .font(.system(.title3, design: .default, weight: isToday || selected ? .semibold : .regular)).monospacedDigit()
            .frame(width: 36, height: 36)
        if isToday {
            text.foregroundStyle(Color.white).glassEffect(.regular.tint(Color.accentColor), in: .circle)
                .overlay { if selected { Circle().strokeBorder(TT.textPrimary.opacity(0.9), lineWidth: 2).matchedGeometryEffect(id: "selection", in: namespace) } }
        } else if selected {
            text.foregroundStyle(scheme == .dark ? Color.black : Color.white)
                .background { Circle().fill(TT.textPrimary).matchedGeometryEffect(id: "selection", in: namespace) }
        } else {
            text.foregroundStyle(cell.isHoliday ? TT.kindHoliday : (cell.inMonth ? (cell.isWeekend ? TT.textSecondary : TT.textPrimary) : TT.textTertiary))
        }
    }

    private var label: String {
        var parts = [Self.longDay(cell.day)]
        if isToday { parts.append(String(localized: "time.today")) }
        parts += cell.info.holidays.map(\.name)
        parts += cell.info.schoolHolidays.map(\.name)
        parts += cell.info.absences.map { "\($0.kind.plainName), \($0.status.plainName)" }
        if let plan = cell.info.plan { parts.append(String(localized: "calendar.plan_label \(plan.mode.plainName)")) }
        return parts.joined(separator: ", ")
    }
}

extension MonthDayCell {
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
