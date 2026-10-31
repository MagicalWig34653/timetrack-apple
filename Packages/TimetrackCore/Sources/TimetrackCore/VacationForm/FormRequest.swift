import Foundation

// Port of the PWA's `days.ts`, `sources.ts` (resolve) and `request.ts` (AB1).

public struct FormDayRange: Sendable, Hashable {
    public var from: LocalDay
    public var to: LocalDay
    public init(from: LocalDay, to: LocalDay) {
        self.from = from
        self.to = to
    }
}

/// Everything a request provides at generation time.
public struct FormRequestData: Sendable, Hashable {
    public var from: LocalDay
    public var to: LocalDay
    public var today: LocalDay
    public var substitute = ""
    public var entitlementYearHalfDays = 0
    public var entitlementTotalHalfDays = 0
    public var carryOverHalfDays = 0
    public var adjustmentHalfDays = 0
    public var restBeforeHalfDays = 0
    public var restAfterHalfDays = 0
    public var workingDays = 0.0
    public var freeRanges: [FormDayRange] = []

    public init(from: LocalDay, to: LocalDay, today: LocalDay) {
        self.from = from
        self.to = to
        self.today = today
    }
}

public enum FormFreeReason: Sendable { case weekend, holiday, nonWorking }

public enum FormDays_ {} // namespace guard (keeps the file's helpers grouped)

public enum FormCalendar {
    /// Every ISO date of an inclusive span; empty when `to` lies before `from`. Capped like the PWA (a request spans weeks, never years).
    public static func dates(from: LocalDay, to: LocalDay) -> [LocalDay] {
        var result: [LocalDay] = []
        var date = from
        while date <= to {
            result.append(date)
            if result.count > 800 { break }
            guard let next = LocalDays.adding(1, to: date) else { break }
            date = next
        }
        return result
    }

    private static func model(on date: LocalDay, _ models: [WorkModel]) -> WorkModel? {
        models.filter { $0.validFrom <= date && ($0.validTo.map { date <= $0 } ?? true) }.max { $0.validFrom < $1.validFrom }
    }

    /// Whether the day is a working day by the work model valid on that date (no model: Monday to Friday) and no public holiday.
    /// School holidays do not free a day. Nil for a working day, otherwise the reason.
    public static func freeReason(_ date: LocalDay, models: [WorkModel], holidays: [CalendarDay]) -> FormFreeReason? {
        if holidays.contains(where: { $0.kind == .holiday && $0.startDate <= date && date <= $0.endDate }) { return .holiday }
        let weekday = LocalDays.isoWeekday(date) ?? 1
        let model = model(on: date, models)
        let workdays = model?.workdays ?? [1, 2, 3, 4, 5]
        if !workdays.contains(weekday) { return weekday >= 6 ? .weekend : .nonWorking }
        if model?.dailyTargetSeconds?[String(weekday)] == 0 { return .nonWorking }
        return nil
    }

    /// Merges dates into ranges of consecutive calendar days.
    public static func ranges(of dates: [LocalDay]) -> [FormDayRange] {
        var result: [FormDayRange] = []
        for date in Set(dates).sorted() {
            if let last = result.last, LocalDays.adding(1, to: last.to) == date {
                result[result.count - 1].to = date
            } else {
                result.append(FormDayRange(from: date, to: date))
            }
        }
        return result
    }

    /// Working days in the span (public holidays and free weekdays excluded). A half day at the start or end removes half a day
    /// when that day is a working day; both flags on a one-day span count once.
    public static func workingDays(from: LocalDay, to: LocalDay, models: [WorkModel], holidays: [CalendarDay],
                                   halfDayStart: Bool = false, halfDayEnd: Bool = false) -> Double {
        let days = dates(from: from, to: to)
        var total = Double(days.filter { freeReason($0, models: models, holidays: holidays) == nil }.count)
        var halves: Set<LocalDay> = []
        if halfDayStart { halves.insert(from) }
        if halfDayEnd { halves.insert(to) }
        for date in halves where days.contains(date) && freeReason(date, models: models, holidays: holidays) == nil { total -= 0.5 }
        return total
    }

    /// Fits ranges into `slots` places of a form; the overflow is reported so the UI can warn instead of silently dropping days.
    public static func fit(_ ranges: [FormDayRange], slots: Int) -> (shown: [FormDayRange], overflow: [FormDayRange]) {
        let count = max(slots, 0)
        return (Array(ranges.prefix(count)), Array(ranges.dropFirst(count)))
    }
}

public struct FormRequestInputs: Sendable {
    public var from: LocalDay
    public var to: LocalDay
    public var halfDayStart = false
    public var halfDayEnd = false
    public var today: LocalDay
    public var substitute = ""
    public var balance: VacationBalance
    public var models: [WorkModel]
    public var holidays: [CalendarDay]
    /// True when the absence already counts in the balance as planned or booked vacation.
    public var inBalance: Bool

    public init(from: LocalDay, to: LocalDay, halfDayStart: Bool = false, halfDayEnd: Bool = false, today: LocalDay, substitute: String = "",
                balance: VacationBalance, models: [WorkModel], holidays: [CalendarDay], inBalance: Bool) {
        self.from = from
        self.to = to
        self.halfDayStart = halfDayStart
        self.halfDayEnd = halfDayEnd
        self.today = today
        self.substitute = substitute
        self.balance = balance
        self.models = models
        self.holidays = holidays
        self.inBalance = inBalance
    }
}

public extension FormRequestData {
    /// Everything the data sources need, derived from the balance, the work models and the holidays (`buildRequestData` of the PWA).
    init(_ input: FormRequestInputs) {
        let balance = input.balance
        self.init(from: input.from, to: input.to, today: input.today)
        substitute = input.substitute
        workingDays = FormCalendar.workingDays(from: input.from, to: input.to, models: input.models, holidays: input.holidays,
                                               halfDayStart: input.halfDayStart, halfDayEnd: input.halfDayEnd)
        let requestHalfDays = Int((workingDays * 2).rounded())
        // With a snapshot the stored remaining days replace entitlement and carry-over (balance semantics), so they stand in for the total.
        let base = balance.snapshotDate != nil ? (balance.snapshotRemainingHalfDays ?? 0) : balance.entitlementHalfDays + balance.carryOverHalfDays
        let restBefore = balance.availableAfterPlannedHalfDays + (input.inBalance ? requestHalfDays : 0)
        entitlementYearHalfDays = balance.snapshotDate != nil ? (balance.snapshotRemainingHalfDays ?? 0) : balance.entitlementHalfDays
        entitlementTotalHalfDays = base + balance.adjustmentHalfDays
        carryOverHalfDays = balance.carryOverHalfDays
        adjustmentHalfDays = balance.adjustmentHalfDays
        restBeforeHalfDays = restBefore
        restAfterHalfDays = restBefore - requestHalfDays
        freeRanges = FormCalendar.ranges(of: FormCalendar.dates(from: input.from, to: input.to)
            .filter { FormCalendar.freeReason($0, models: input.models, holidays: input.holidays) != nil })
    }
}

/// What a binding produces for one target.
public enum FormValue: Sendable, Equatable {
    case text(String)
    case flag(Bool)
    /// Leave the field empty.
    case empty
}

public extension FormMapping {
    /// Value a binding produces for a request (`resolveBinding` of the PWA).
    func resolve(_ binding: FormBinding, _ request: FormRequestData) -> FormValue {
        func nonEmpty(_ value: String) -> FormValue {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .empty : .text(trimmed)
        }
        func days(_ halfDays: Int) -> FormValue { .text(FormDays.format(Double(halfDays) / 2)) }
        let format = binding.dateFormat ?? dateFormat
        func range(_ range: FormDayRange) -> String {
            range.from == range.to ? format.format(range.from) : "\(format.format(range.from)) - \(format.format(range.to))"
        }
        func freeRange() -> FormDayRange? {
            let position = min(max(binding.index ?? 1, 1), maxFreeRanges)
            return position <= request.freeRanges.count ? request.freeRanges[position - 1] : nil
        }
        switch binding.source {
        case .lastName: return nonEmpty(person.lastName)
        case .firstName: return nonEmpty(person.firstName)
        case .fullName: return nonEmpty("\(person.firstName) \(person.lastName)")
        case .personnelNo: return nonEmpty(person.personnelNo)
        case .department: return nonEmpty(person.department)
        case .place: return nonEmpty(person.place)
        case .entitlementTotal: return days(request.entitlementTotalHalfDays)
        case .entitlementYear: return days(request.entitlementYearHalfDays)
        case .carryOver: return days(request.carryOverHalfDays)
        case .additional: return days(max(request.adjustmentHalfDays, 0))
        case .paidOut: return days(max(-request.adjustmentHalfDays, 0))
        case .restBefore: return days(request.restBeforeHalfDays)
        case .restAfter: return days(request.restAfterHalfDays)
        case .dateFrom: return .text(format.format(request.from))
        case .dateTo: return .text(format.format(request.to))
        case .dateRange: return .text(range(FormDayRange(from: request.from, to: request.to)))
        case .workingDays: return .text(FormDays.format(request.workingDays))
        case .freeRangeFrom: return freeRange().map { .text(format.format($0.from)) } ?? .empty
        case .freeRangeTo: return freeRange().map { .text(format.format($0.to)) } ?? .empty
        case .freeRange: return freeRange().map { .text(range($0)) } ?? .empty
        case .freeDaysCount:
            // Inclusive day count of every range (calendar days, like the PWA).
            let total = request.freeRanges.reduce(0) { $0 + ((LocalDays.daysBetween($1.from, $1.to) ?? 0) + 1) }
            return .text(String(total))
        case .hasFreeDays: return .flag(!request.freeRanges.isEmpty)
        case .substitute: return nonEmpty(request.substitute)
        case .today: return .text(format.format(request.today))
        case .fixedText: return nonEmpty(binding.text ?? "")
        case .fixedCheckbox: return .flag(binding.checked == true)
        }
    }

    /// Highest free-range position the template addresses; 0 when it has no such field.
    var freeRangeSlots: Int {
        let bindings = Array(fields.values) + overlays.map(\.binding)
        return bindings.reduce(0) { result, binding in
            switch binding.source {
            case .freeRangeFrom, .freeRangeTo, .freeRange: max(result, binding.index ?? 1)
            default: result
            }
        }
    }
}

/// File name for the generated request: `Urlaubsantrag_2026-07-06_2026-07-17.pdf`.
public func vacationRequestFileName(from: LocalDay, to: LocalDay) -> String { "Urlaubsantrag_\(from)_\(to).pdf" }


/// AUD3-B: which absences offer "Urlaubsantrag erstellen" (same rule as the PWA: vacation that is neither cancelled nor rejected).
public enum VacationRequestEligibility {
    public static func isEligible(_ absence: Absence) -> Bool {
        absence.kind == .vacation && absence.status != .cancelled && absence.status != .rejected
    }

    /// Eligible absences, soonest first (start date, then end date).
    public static func eligible(in absences: [Absence]) -> [Absence] {
        absences.filter(isEligible).sorted { ($0.startDate, $0.endDate) < ($1.startDate, $1.endDate) }
    }
}
