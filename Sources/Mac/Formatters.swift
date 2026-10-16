import SwiftUI
import TimetrackCore
import TimetrackDesign

extension Date {
    /// Wall-clock time in the work model's zone (`HH:mm`), independent of the device's own zone.
    func clockText(in zone: TimeZone) -> String {
        formatted(Date.FormatStyle(timeZone: zone).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

extension SegmentKind {
    var titleKey: LocalizedStringKey { ttTitle }
    var symbol: String { ttSymbol }
}

extension TimetrackError {
    var messageText: Text { Text(verbatim: germanDescription) }
}

/// "Fr., 16. Okt." for a `YYYY-MM-DD` label.
func dayTitle(_ day: LocalDay, calendar: DayCalendar) -> String {
    guard let start = calendar.interval(of: day)?.start else { return day }
    return start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
}

/// "12. – 18. Okt." (month only once when both ends share it).
func weekRangeText(start: LocalDay, end: LocalDay, calendar: DayCalendar) -> String {
    guard let first = calendar.interval(of: start)?.start, let last = calendar.interval(of: end)?.start else { return "" }
    let zone = calendar.timeZone
    let sameMonth = Calendar.current.dateComponents(in: zone, from: first).month == Calendar.current.dateComponents(in: zone, from: last).month
    let from = first.formatted(sameMonth ? Date.FormatStyle(timeZone: zone).day() : Date.FormatStyle(timeZone: zone).day().month(.abbreviated))
    return "\(from) – \(last.formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated)))"
}

func breakHintKey(_ code: String) -> LocalizedStringKey {
    switch code {
    case "break_missing_30": "hint.break_missing_30"
    case "break_missing_45": "hint.break_missing_45"
    case "break_part_too_short": "hint.break_part_too_short"
    case "work_over_6h_without_break": "hint.work_over_6h_without_break"
    default: "hint.unknown"
    }
}

func markKey(_ mark: DayMarkKind) -> LocalizedStringKey {
    switch mark {
    case .holiday: "mark.holiday"
    case .vacation: "mark.vacation"
    case .sick: "mark.sick"
    case .excused: "mark.excused"
    case .schoolCredit: "mark.school_credit"
    case .unmarked, .unknown: "time.no_entries"
    }
}

func markTint(_ mark: DayMarkKind) -> Color {
    switch mark {
    case .holiday: TT.kindHoliday
    case .vacation: TT.kindVacation
    case .sick: TT.kindSick
    case .excused: TT.kindExcused
    case .schoolCredit: TT.kindSchool
    case .unmarked, .unknown: TT.textSecondary
    }
}

func markSymbol(_ mark: DayMarkKind) -> String {
    switch mark {
    case .holiday: "party.popper.fill"
    case .vacation: "beach.umbrella.fill"
    case .sick: "cross.case.fill"
    case .excused: "checkmark.seal.fill"
    case .schoolCredit: "graduationcap.fill"
    case .unmarked, .unknown: "minus"
    }
}

/// Tone of a day difference: behind target = warning, otherwise success; zero is neutral.
func deltaTone(_ seconds: Int) -> TTTone { seconds < 0 ? .warning : (seconds > 0 ? .success : .neutral) }

/// Adapter from a backend segment to the design system's row.
struct SegmentRow: View {
    let segment: Segment
    let zone: TimeZone

    var body: some View {
        let start = segment.startedAt.clockText(in: zone)
        SegmentRowCell(
            kind: segment.kind,
            timeRange: "\(start) – \(segment.endedAt.map { $0.clockText(in: zone) } ?? "…")",
            duration: segment.endedAt.map { DurationFormat.hoursMinutes(Int($0.timeIntervalSince(segment.startedAt))) },
            note: segment.note,
            isRunning: segment.isRunning,
            needsReview: segment.needsReview)
    }
}

struct ErrorBannerView: View {
    let error: TimetrackError
    let retry: () -> Void

    var body: some View {
        ErrorBanner(message: error.germanDescription, retryTitle: "common.retry", retry: retry)
            .accessibilityIdentifier("error.banner")
    }
}
