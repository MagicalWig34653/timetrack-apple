import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// Shared by the iOS/iPadOS and macOS targets (planning module: absences, calendar, vacation settings).
// Strings live in each app's Localizable.xcstrings; code stays platform-neutral.

/// Formatting and labels for planning screens.
enum PlanFormat {
    static func date(_ day: LocalDay, calendar: DayCalendar) -> Date? { calendar.interval(of: day)?.start }

    /// "Montag, 20. Oktober"
    static func longDay(_ day: LocalDay, calendar: DayCalendar) -> String {
        guard let start = date(day, calendar: calendar) else { return day }
        return start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.wide).day().month(.wide))
    }

    /// "20. Okt." (short, no weekday)
    static func shortDay(_ day: LocalDay, calendar: DayCalendar) -> String {
        guard let start = date(day, calendar: calendar) else { return day }
        return start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).day().month(.abbreviated))
    }

    /// "20. Okt. 2026"
    static func fullDay(_ day: LocalDay, calendar: DayCalendar) -> String {
        guard let start = date(day, calendar: calendar) else { return day }
        return start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).day().month(.abbreviated).year())
    }

    static func range(_ start: LocalDay, _ end: LocalDay, calendar: DayCalendar) -> String {
        start == end ? shortDay(start, calendar: calendar) : "\(shortDay(start, calendar: calendar)) – \(shortDay(end, calendar: calendar))"
    }

    /// "Oktober 2026"
    static func monthTitle(year: Int, month: Int, calendar: DayCalendar) -> String {
        guard let start = date(LocalDays.format(year: year, month: month, day: 1), calendar: calendar) else { return "\(month)/\(year)" }
        return start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.wide).year())
    }

    static func monthName(_ month: Int, calendar: DayCalendar) -> String {
        guard let start = date(LocalDays.format(year: 2026, month: month, day: 1), calendar: calendar) else { return "\(month)" }
        return start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.wide))
    }

    /// Monday-first short weekday names ("Mo.", "Di.", ...).
    static var weekdayHeaders: [String] {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = Locale.autoupdatingCurrent
        let symbols = gregorian.shortWeekdaySymbols
        return Array(symbols[1...]) + [symbols[0]]
    }

    /// "1 Tag", "2,5 Tage", "0,5 Tage" from half days.
    static func days(_ halfDays: Int) -> String {
        let number = HalfDayFormat.days(halfDays)
        return halfDays == 2 ? String(localized: "plan.unit.day \(number)") : String(localized: "plan.unit.days \(number)")
    }

    static func local(_ day: LocalDay, calendar: DayCalendar) -> Date { date(day, calendar: calendar).map { $0.addingTimeInterval(12 * 3600) } ?? .now }

    static func day(_ date: Date, calendar: DayCalendar) -> LocalDay { calendar.day(for: date) }
}

extension AbsenceKind {
    static let selectable: [AbsenceKind] = [.vacation, .sick, .excused, .other]

    var detailKey: LocalizedStringKey {
        switch self {
        case .vacation: "plan.kind.vacation.hint"
        case .sick: "plan.kind.sick.hint"
        case .excused: "plan.kind.excused.hint"
        case .other, .unknown: "plan.kind.other.hint"
        }
    }

    /// Title for the "register" quick actions ("Urlaub eintragen", "Krank melden").
    var actionKey: LocalizedStringKey {
        switch self {
        case .vacation: "plan.action.vacation"
        case .sick: "plan.action.sick"
        case .excused: "plan.action.excused"
        case .other, .unknown: "plan.action.other"
        }
    }

    var shortKey: LocalizedStringKey {
        switch self {
        case .vacation: "plan.short.vacation"
        case .sick: "plan.short.sick"
        case .excused: "plan.short.excused"
        case .other, .unknown: "plan.short.other"
        }
    }

    var plainName: String {
        switch self {
        case .vacation: String(localized: "absence.vacation")
        case .sick: String(localized: "absence.sick")
        case .excused: String(localized: "absence.excused")
        case .other, .unknown: String(localized: "absence.other")
        }
    }
}

extension AbsenceStatus {
    /// Statuses the editor offers: vacation has the full request flow, everything else only planned/taken (ADR-0005).
    static func options(for kind: AbsenceKind, keeping current: AbsenceStatus?) -> [AbsenceStatus] {
        var list: [AbsenceStatus] = kind == .vacation ? [.planned, .requested, .approved, .taken] : [.planned, .taken]
        if let current, current != .unknown, !list.contains(current) { list.append(current) }
        return list
    }

    var plainName: String {
        switch self {
        case .planned: String(localized: "absence.status.planned")
        case .requested: String(localized: "absence.status.requested")
        case .approved: String(localized: "absence.status.approved")
        case .taken: String(localized: "absence.status.taken")
        case .rejected: String(localized: "absence.status.rejected")
        case .cancelled: String(localized: "absence.status.cancelled")
        case .unknown: String(localized: "absence.status.unknown")
        }
    }

    var pickerKey: LocalizedStringKey {
        switch self {
        case .planned: "plan.status.planned"
        case .requested: "plan.status.requested"
        case .approved: "plan.status.approved"
        case .taken: "plan.status.taken"
        case .rejected: "plan.status.rejected"
        case .cancelled: "plan.status.cancelled"
        case .unknown: "plan.status.unknown"
        }
    }

    var tone: TTTone {
        switch self {
        case .approved, .taken: .success
        case .planned, .requested: .accent
        case .rejected, .cancelled: .danger
        case .unknown: .neutral
        }
    }
}

extension DocumentStatus {
    var pickerKey: LocalizedStringKey {
        switch self {
        case .notNeeded, .unknown: "plan.document.not_needed"
        case .pending: "plan.document.pending"
        case .submitted: "plan.document.submitted"
        }
    }

    var plainName: String {
        switch self {
        case .notNeeded, .unknown: String(localized: "plan.document.not_needed")
        case .pending: String(localized: "plan.document.pending")
        case .submitted: String(localized: "plan.document.submitted")
        }
    }
}

extension PlanMode {
    var title: LocalizedStringKey {
        switch self {
        case .office: "plan.mode.office"
        case .home: "plan.mode.home"
        case .customer: "plan.mode.customer"
        case .school: "plan.mode.school"
        case .off: "plan.mode.off"
        case .unknown: "plan.mode.unknown"
        }
    }

    var plainName: String {
        switch self {
        case .office: String(localized: "plan.mode.office")
        case .home: String(localized: "plan.mode.home")
        case .customer: String(localized: "plan.mode.customer")
        case .school: String(localized: "plan.mode.school")
        case .off: String(localized: "plan.mode.off")
        case .unknown: String(localized: "plan.mode.unknown")
        }
    }

    var symbol: String {
        switch self {
        case .office: "building.2.fill"
        case .home: "house.fill"
        case .customer: "person.2.fill"
        case .school: "graduationcap.fill"
        case .off: "moon.zzz.fill"
        case .unknown: "questionmark"
        }
    }

    var tint: Color {
        switch self {
        case .office: Color(red: 0.06, green: 0.60, blue: 0.40)
        case .home: TT.kindExcused
        case .customer: TT.kindTravel
        case .school: TT.kindSchool
        case .off, .unknown: TT.textSecondary
        }
    }
}

/// Regions the backend's holiday calculation knows (ISO 3166-2). Convenience list; the server validates.
enum VacationRegions {
    static let all: [(code: String, name: String)] = [
        ("DE-ST", "Sachsen-Anhalt"), ("DE-BW", "Baden-Württemberg"), ("DE-BY", "Bayern"), ("DE-BE", "Berlin"), ("DE-BB", "Brandenburg"),
        ("DE-HB", "Bremen"), ("DE-HH", "Hamburg"), ("DE-HE", "Hessen"), ("DE-MV", "Mecklenburg-Vorpommern"), ("DE-NI", "Niedersachsen"),
        ("DE-NW", "Nordrhein-Westfalen"), ("DE-RP", "Rheinland-Pfalz"), ("DE-SL", "Saarland"), ("DE-SN", "Sachsen"),
        ("DE-SH", "Schleswig-Holstein"), ("DE-TH", "Thüringen"), ("DE", "Bundesweit"),
    ]
    static func name(_ code: String) -> String { all.first { $0.code == code }?.name ?? code }
}

/// Layout switch: iPad/Mac use two columns, iPhone one stream.
func planningIsWide(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
    #if os(macOS)
    true
    #else
    sizeClass == .regular
    #endif
}

extension View {
    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

/// Bridges a `LocalDay` to a `Date` for `DatePicker` (noon of the day in the work model's zone).
func dayBinding(_ binding: Binding<LocalDay>, calendar: DayCalendar) -> Binding<Date> {
    Binding(get: { PlanFormat.local(binding.wrappedValue, calendar: calendar) }, set: { binding.wrappedValue = calendar.day(for: $0) })
}

/// A labelled row inside a `FormSection` (padding like the rest of the app's editors).
struct EditorRow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Request to open the absence editor: new (`editing == nil`) or existing.
struct AbsenceRequest: Identifiable {
    let id = UUID()
    var kind: AbsenceKind
    var start: LocalDay
    var end: LocalDay
    var editing: Absence?
}

/// Request to open another planning sheet.
enum PlanSheet: Identifiable {
    case plan(LocalDay)
    case customDay(LocalDay)
    case manualEntry(LocalDay)
    case eventDraft(LocalDay, DeviceEvent) // E1: proposal derived from a device calendar event
    case settings

    var id: String {
        switch self {
        case .plan(let day): "plan-\(day)"
        case .customDay(let day): "custom-\(day)"
        case .manualEntry(let day): "entry-\(day)"
        case .eventDraft(let day, let event): "event-\(day)-\(event.id)"
        case .settings: "settings"
        }
    }
}
