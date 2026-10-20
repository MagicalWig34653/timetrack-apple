import SwiftUI
import TimetrackCore
import TimetrackDesign

// N1a: week overview, week planner and vacation planner (iOS/iPadOS). Strings: key prefix "wk." in Sources/iOS/Localizable.xcstrings.

/// Localized strings with the key prefix `wk.` in the app catalog (German source). Arguments replace `%@` / `%d` in order.
enum W {
    static func s(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString("wk." + key, bundle: .main, value: key, comment: "")
        return args.isEmpty ? format : String(format: format, arguments: args)
    }
    static func t(_ key: String, _ args: CVarArg...) -> Text {
        let format = NSLocalizedString("wk." + key, bundle: .main, value: key, comment: "")
        return Text(verbatim: args.isEmpty ? format : String(format: format, arguments: args))
    }
}

/// "1,5" for 1.5, "2" for 2 (German decimal comma).
func weekDecimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "de_DE")))
}

func weekDays(_ value: Double) -> String { W.s(value == 1 ? "days.one" : "days.other", weekDecimal(value)) }

extension WeekMark {
    var symbol: String {
        switch self {
        case .work: "briefcase.fill"
        case .school: "graduationcap.fill"
        case .vacation: "beach.umbrella.fill"
        case .sick: "cross.case.fill"
        case .holiday: "party.popper.fill"
        case .excused: "checkmark.seal.fill"
        case .off, .unknown: "moon.zzz.fill"
        }
    }
    var tint: Color {
        switch self {
        case .work: TT.kindWork
        case .school: TT.kindSchool
        case .vacation: TT.kindVacation
        case .sick: TT.kindSick
        case .holiday: TT.kindHoliday
        case .excused: TT.kindExcused
        case .off, .unknown: TT.textSecondary
        }
    }
    var label: String { W.s("mark.\(self == .unknown ? "off" : rawValue)") }
}

extension PlanBlockedBy {
    var label: String { W.s("blocked.\(self == .unknown ? "excused" : rawValue)") }
}

/// Weekday plus date, e.g. "Mo., 26. Okt.".
func weekDayTitle(_ day: LocalDay, calendar: DayCalendar) -> String { dayTitle(day, calendar: calendar) }

/// Week navigation bar shared by overview and planner: KW, date range, previous/next, jump to this week.
struct WeekNavigator: View {
    let weekNumber: Int
    let monday: LocalDay
    let sunday: LocalDay
    let calendar: DayCalendar
    let isCurrent: Bool
    let previous: () -> Void
    let next: () -> Void
    let current: () -> Void

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: TT.Space.s) {
            Button { TTHaptics.play(.softTap); previous() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel(W.t("nav.previous")).accessibilityIdentifier("week.previous")
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(verbatim: W.s("nav.kw", weekNumber)).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary).accessibilityIdentifier("week.title")
                Text(verbatim: weekRangeText(start: monday, end: sunday, calendar: calendar)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Button { TTHaptics.play(.softTap); next() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel(W.t("nav.next")).accessibilityIdentifier("week.next")
        }
        .buttonStyle(.borderless)
        if !isCurrent {
            Button { current() } label: { W.t("nav.this_week").frame(minHeight: 44) }
                .buttonStyle(.borderless).font(TTFont.meta).accessibilityIdentifier("week.current")
                .frame(maxWidth: .infinity)
        }
        }
    }
}

struct SummaryTile: View {
    let title: String
    let value: String
    var caption: String?
    var tint: Color = TT.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(1)
            Text(verbatim: value).font(TTFont.stat).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.5)
            if let caption { Text(verbatim: caption).font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Error banner for week screens; 503 `database_unavailable` and other failures offer a retry.
struct WeekErrorBanner: View {
    let error: TimetrackError
    let retry: () -> Void
    var body: some View {
        ErrorBanner(message: error.germanDescription, retryTitle: "common.retry", retry: retry).accessibilityIdentifier("week.error")
    }
}
