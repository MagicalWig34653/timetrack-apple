import Foundation
import Observation
import TimetrackCore

/// Everything the calendar shows for one local day.
public struct CalendarDayInfo: Sendable, Equatable {
    public let day: LocalDay
    public var holidays: [CalendarDay] = []
    public var schoolHolidays: [CalendarDay] = []
    public var absences: [Absence] = []
    public var plan: PlanDay?

    public var isHoliday: Bool { !holidays.isEmpty }
}

/// State of the "Kalender" tab (module `planning`): month grid, selection, range selection and optimistic edits.
/// Absences are shown optimistically: the cell changes before the server answers and is reconciled with the response.
@MainActor
@Observable
public final class CalendarStore {
    public private(set) var year: Int
    public private(set) var month: Int
    public private(set) var holidays: [CalendarDay] = []
    public private(set) var absences: [Absence] = []
    public private(set) var planDays: [LocalDay: PlanDay] = [:]
    public private(set) var detail: DayEvaluation?
    public private(set) var isLoading = false
    public var selectedDay: LocalDay?
    public var error: TimetrackError?

    /// Range mode: first tap sets `rangeStart`, second tap `rangeEnd`.
    public var isRangeMode = false
    public private(set) var rangeStart: LocalDay?
    public private(set) var rangeEnd: LocalDay?

    public let calendar: DayCalendar
    private let client: APIClient
    /// Called after a successful absence change so the Urlaub tab can refresh its balance.
    public var onAbsencesChanged: (@MainActor () -> Void)?
    private var loadGeneration = 0

    public init(client: APIClient, calendar: DayCalendar, now: Date = .now) {
        self.client = client
        self.calendar = calendar
        let parts = LocalDays.parse(calendar.day(for: now))
        self.year = parts?.year ?? 2026
        self.month = parts?.month ?? 1
    }

    public var today: LocalDay { calendar.day(for: .now) }

    // MARK: - Grid

    public var firstOfMonth: LocalDay { LocalDays.format(year: year, month: month, day: 1) }

    /// Days of the visible grid: whole Monday-first weeks covering the month.
    public var gridDays: [LocalDay] {
        guard let first = LocalDays.mondayOfWeek(containing: firstOfMonth) else { return [] }
        let lastOfMonth = LocalDays.adding(-1, to: Self.firstOfMonth(year: month == 12 ? year + 1 : year, month: month == 12 ? 1 : month + 1)) ?? firstOfMonth
        let span = (LocalDays.daysBetween(first, lastOfMonth) ?? 34) + 1
        let weeks = Int((Double(span) / 7).rounded(.up))
        return (0..<(weeks * 7)).compactMap { LocalDays.adding($0, to: first) }
    }

    private static func firstOfMonth(year: Int, month: Int) -> LocalDay { LocalDays.format(year: year, month: month, day: 1) }

    public func isInVisibleMonth(_ day: LocalDay) -> Bool {
        guard let p = LocalDays.parse(day) else { return false }
        return p.year == year && p.month == month
    }

    public func shiftMonths(_ count: Int) async {
        let index = year * 12 + (month - 1) + count
        year = index / 12
        month = index % 12 + 1
        await load()
    }

    public func goTo(year: Int, month: Int) async {
        self.year = year
        self.month = month
        await load()
    }

    public func goToToday() async {
        let parts = LocalDays.parse(today)
        year = parts?.year ?? year
        month = parts?.month ?? month
        selectedDay = today
        await load()
        await loadDetail()
    }

    // MARK: - Loading and merging

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        guard let from = gridDays.first, let to = gridDays.last else { return }
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let years = Set([from, to].compactMap { LocalDays.parse($0)?.year })
            async let absenceResult = client.listAbsences(from: from, to: to)
            async let planResult = client.listPlanDays(from: from, to: to)
            var loadedHolidays: [CalendarDay] = []
            for year in years.sorted() { loadedHolidays += try await client.listHolidays(year: year) }
            let (loadedAbsences, loadedPlan) = try await (absenceResult, planResult)
            guard generation == loadGeneration else { return }
            holidays = loadedHolidays
            absences = Self.visible(loadedAbsences)
            planDays = Dictionary(loadedPlan.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
            error = nil
        } catch {
            record(error)
        }
    }

    private static func visible(_ list: [Absence]) -> [Absence] {
        list.filter { $0.status != .cancelled && $0.status != .rejected }.sorted { ($0.startDate, $0.id.uuidString) < ($1.startDate, $1.id.uuidString) }
    }

    public func info(for day: LocalDay) -> CalendarDayInfo {
        var info = CalendarDayInfo(day: day)
        for entry in holidays where entry.covers(day) {
            if entry.kind == .schoolHoliday { info.schoolHolidays.append(entry) } else { info.holidays.append(entry) }
        }
        info.absences = absences.filter { $0.startDate <= day && day <= $0.endDate }
        info.plan = planDays[day]
        return info
    }

    public func loadDetail() async {
        guard let day = selectedDay else {
            detail = nil
            return
        }
        do {
            let evaluation = try await client.getDay(day)
            if selectedDay == day { detail = evaluation }
        } catch {
            if selectedDay == day { detail = nil }
        }
    }

    public func select(_ day: LocalDay?) async {
        selectedDay = day
        detail = nil
        await loadDetail()
    }

    // MARK: - Range selection

    public func beginRange(at day: LocalDay) {
        isRangeMode = true
        rangeStart = day
        rangeEnd = nil
    }

    public func cancelRange() {
        isRangeMode = false
        rangeStart = nil
        rangeEnd = nil
    }

    /// First tap sets the start, the second the end (order is normalised). A third tap starts over.
    public func tapInRangeMode(_ day: LocalDay) {
        if rangeStart == nil || rangeEnd != nil {
            rangeStart = day
            rangeEnd = nil
        } else if let start = rangeStart {
            rangeStart = min(start, day)
            rangeEnd = max(start, day)
        }
    }

    /// The chosen range (a single tapped start day counts as a one-day range).
    public var chosenRange: (start: LocalDay, end: LocalDay)? {
        guard let start = rangeStart else { return nil }
        return (start, rangeEnd ?? start)
    }

    public func isInRange(_ day: LocalDay) -> Bool {
        guard let range = chosenRange, isRangeMode else { return false }
        return range.start <= day && day <= range.end
    }

    // MARK: - Absences (optimistic)

    /// Creates or updates an absence. The grid shows the change immediately and is reconciled with the server's answer;
    /// on failure the previous state returns and `error` is set.
    @discardableResult
    public func saveAbsence(_ input: AbsenceInput, editing: Absence?) async -> Absence? {
        let before = absences
        let draft = Absence(id: editing?.id ?? UUID(), version: editing?.version ?? 0, kind: input.kind, startDate: input.startDate, endDate: input.endDate,
                            halfDayStart: input.halfDayStart, halfDayEnd: input.halfDayEnd, status: input.status, note: input.note,
                            countedHalfDays: editing?.countedHalfDays ?? 0, documentStatus: input.documentStatus,
                            documentSubmittedOn: input.documentSubmittedOn, documentReferenceStart: input.documentReferenceStart,
                            documentReferenceEnd: input.documentReferenceEnd)
        absences = Self.visible(absences.filter { $0.id != draft.id } + [draft])
        do {
            let stored: Absence
            if let editing {
                stored = try await client.updateAbsence(id: editing.id, input, ifMatchVersion: editing.version)
            } else {
                stored = try await client.createAbsence(input)
            }
            absences = Self.visible(absences.filter { $0.id != draft.id } + [stored])
            error = nil
            onAbsencesChanged?()
            await loadDetail()
            return stored
        } catch {
            absences = before
            record(error)
            return nil
        }
    }

    @discardableResult
    public func deleteAbsence(_ absence: Absence) async -> Bool {
        let before = absences
        absences = absences.filter { $0.id != absence.id }
        do {
            try await client.deleteAbsence(id: absence.id)
            error = nil
            onAbsencesChanged?()
            await loadDetail()
            return true
        } catch {
            absences = before
            record(error)
            return false
        }
    }

    /// Marks a sick note as submitted today (convenience from the day sheet).
    @discardableResult
    public func markDocumentSubmitted(_ absence: Absence) async -> Bool {
        var input = AbsenceInput(absence)
        input.documentStatus = .submitted
        input.documentSubmittedOn = input.documentSubmittedOn ?? today
        return await saveAbsence(input, editing: absence) != nil
    }

    /// Cancels an absence (status `cancelled`, the record stays on the server; it disappears from the calendar).
    @discardableResult
    public func cancelAbsence(_ absence: Absence) async -> Bool {
        var input = AbsenceInput(absence)
        input.status = .cancelled
        return await saveAbsence(input, editing: absence) != nil
    }

    // MARK: - Plan days (optimistic)

    @discardableResult
    public func savePlan(day: LocalDay, _ input: PlanDayInput) async -> Bool {
        let before = planDays
        planDays[day] = PlanDay(date: day, mode: input.mode, placeId: input.placeId, note: input.note)
        do {
            planDays[day] = try await client.putPlanDay(day, input)
            error = nil
            return true
        } catch {
            planDays = before
            record(error)
            return false
        }
    }

    @discardableResult
    public func removePlan(day: LocalDay) async -> Bool {
        let before = planDays
        planDays[day] = nil
        do {
            try await client.deletePlanDay(day)
            error = nil
            return true
        } catch {
            planDays = before
            record(error)
            return false
        }
    }

    // MARK: - Custom days

    @discardableResult
    public func createCustomDay(_ input: CustomDayInput) async -> Bool {
        do {
            let created = try await client.createCustomDay(input)
            holidays.append(created)
            error = nil
            return true
        } catch {
            record(error)
            return false
        }
    }

    @discardableResult
    public func deleteCustomDay(_ entry: CalendarDay) async -> Bool {
        guard let id = entry.id else { return false }
        let before = holidays
        holidays.removeAll { $0.id == id }
        do {
            try await client.deleteCustomDay(id: id)
            error = nil
            return true
        } catch {
            holidays = before
            record(error)
            return false
        }
    }

    private func record(_ failure: Error) {
        if let failure = failure as? TimetrackError {
            if failure != .cancelled { error = failure }
        } else {
            error = .cancelled
        }
    }
}
