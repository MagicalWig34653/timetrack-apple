import SwiftUI
import TimetrackCore

extension Date {
    /// Wall-clock time in the work model's zone (`HH:mm`), independent of the device's own zone.
    func clockText(in zone: TimeZone) -> String {
        formatted(Date.FormatStyle(timeZone: zone).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

extension SegmentKind {
    var titleKey: LocalizedStringKey {
        switch self {
        case .work, .unknown: "kind.work"
        case .travel: "kind.travel"
        case .school: "kind.school"
        }
    }

    var symbol: String {
        switch self {
        case .work, .unknown: "briefcase"
        case .travel: "car"
        case .school: "graduationcap"
        }
    }
}

extension TimetrackError {
    var messageText: Text { Text(verbatim: germanDescription) }
}

/// "Fr., 16. Okt." for a `YYYY-MM-DD` label.
func dayTitle(_ day: LocalDay, calendar: DayCalendar) -> String {
    guard let start = calendar.interval(of: day)?.start else { return day }
    return start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
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

struct ErrorBanner: View {
    let error: TimetrackError
    let retry: () -> Void

    var body: some View {
        HStack {
            error.messageText
            Spacer()
            Button("common.retry", action: retry)
        }
        .font(.callout)
        .padding(12)
        .background(.red.opacity(0.12), in: .rect(cornerRadius: 12))
        .accessibilityIdentifier("error.banner")
    }
}
