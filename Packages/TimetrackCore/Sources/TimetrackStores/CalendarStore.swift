import Foundation
import Observation
import TimetrackCore

/// Everything the calendar shows for one local day.
public struct CalendarDayInfo: Sendable, Hashable {
    public let day: LocalDay
    public var holidays: [CalendarDay] = []
    public var schoolHolidays: [CalendarDay] = []
    public var absences: [Absence] = []
    public var plan: PlanDay?

    /// A full holiday (public holiday or `full` company day). A `half` company day stays a work day and is only a marker.
    public var isHoliday: Bool { holidays.contains { !$0.isHalfDay } }
    public var hasHalfDay: Bool { holidays.contains { $0.isHalfDay } }
}

/// State of the "Kalender" tab (module `planning`): month grid, selection, range selection and optimistic edits.
/// Absences are shown optimistically: the cell changes before the server answers and is reconciled with the response.
@MainActor
@Observable
public final class CalendarStore {
    public private(set) var year: Int
    public private(set) var month: Int
    public private(set) var holidays: [CalendarDay] = [] { didSet { dataVersion += 1 } }
    public private(set) var absences: [Absence] = [] { didSet { dataVersion += 1 } }
    public private(set) var planDays: [LocalDay: PlanDay] = [:] { didSet { dataVersion += 1 } }
    /// Evaluated days (with their entries) of the loaded window: the day details of the month zoom read from here (Z2).
    public private(set) var evaluations: [LocalDay: DayEvaluation] = [:]
    /// Changes whenever holidays, absences or plan change; page snapshots are valid for one version.
    public private(set) var dataVersion = 0
    public private(set) var detail: DayEvaluation?
    public private(set) var isLoading = false
    public var selectedDay: LocalDay?
    public var error: TimetrackError?
    /// Reports the result of absence, plan and custom-day writes (never loads or navigation).
    public var onOutcome: StoreOutcomeHandler?

    /// Range mode: first tap sets `rangeStart`, second tap `rangeEnd`.
    public var isRangeMode = false
    public private(set) var rangeStart: LocalDay?
    public private(set) var rangeEnd: LocalDay?

    public let calendar: DayCalendar
    private let client: APIClient
    /// Called after a successful absence change so the Urlaub tab can refresh its balance.
    public var onAbsencesChanged: (@MainActor () -> Void)?
    private var loadGeneration = 0

    // Z2: window of loaded data (visible month plus prefetched neighbours), snapshots and measurements.
    /// Months loaded ahead on each side of the visible month.
    public static let prefetchRadius = 1
    /// A covered month older than this is refreshed silently in the background when it becomes visible.
    public static let revalidateAfter: TimeInterval = 90
    public private(set) var loadedRange: ClosedRange<LocalDay>?
    @ObservationIgnored private var holidayYears: Set<Int> = []
    @ObservationIgnored private var fetchedAt: [MonthKey: Date] = [:]
    @ObservationIgnored private var snapshots: [MonthKey: (version: Int, snapshot: MonthSnapshot)] = [:]
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    /// Counters and timings for tests and logs (no UI reads them).
    @ObservationIgnored public private(set) var metrics = Metrics()

    public struct Metrics: Sendable, Equatable {
        public var windowHits = 0
        public var windowMisses = 0
        public var rangeFetches = 0
        public var requests = 0
        public var snapshotBuilds = 0
        public var lastFetchSeconds: Double = 0
        public var lastSnapshotSeconds: Double = 0
    }

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

    public var visibleKey: MonthKey { MonthKey(year: year, month: month) }

    public func shiftMonths(_ count: Int) async {
        showMonth(visibleKey.adding(count))
        await ensureWindow()
    }

    public func goTo(year: Int, month: Int) async {
        showMonth(MonthKey(year: year, month: month))
        await ensureWindow()
    }

    /// Synchronous month switch for the pager: the title and the page change at once, data comes from the prefetched window
    /// (`ensureWindow()` follows and only fetches what is missing).
    public func showMonth(_ key: MonthKey) {
        year = key.year
        month = key.month
    }

    public func goToToday() async {
        let parts = LocalDays.parse(today)
        year = parts?.year ?? year
        month = parts?.month ?? month
        selectedDay = today
        detail = evaluations[today]
        await ensureWindow()
        await loadDetail()
    }

    // MARK: - Loading, window and prefetch (Z2)

    /// Full refresh of the visible month (pull to refresh, app became active). Neighbours stay in place and are revalidated lazily.
    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let key = visibleKey
        let range = key.gridRange
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            try await fetchRange(range.from, range.to, generation: generation)
            guard generation == loadGeneration else { return }
            error = nil
            refreshDetailFromCache()
            warmSnapshots()
            schedulePrefetch()
        } catch {
            record(error, notify: false)
        }
    }

    private func covers(_ key: MonthKey) -> Bool {
        guard let loadedRange else { return false }
        let range = key.gridRange
        return loadedRange.contains(range.from) && loadedRange.contains(range.to)
    }

    /// Makes sure the visible month is loaded (instant when the prefetch already did it) and starts prefetching its neighbours.
    public func ensureWindow() async {
        let key = visibleKey
        if covers(key) {
            metrics.windowHits += 1
            if let at = fetchedAt[key], Date.now.timeIntervalSince(at) > Self.revalidateAfter {
                Task { [weak self] in try? await self?.revalidate(key) }
            }
        } else {
            metrics.windowMisses += 1
            let range = key.gridRange
            let generation = loadGeneration
            isLoading = true
            defer { isLoading = false }
            do {
                try await fetchMissing(range.from, range.to, generation: generation)
                if visibleKey == key { error = nil }
            } catch {
                record(error, notify: false)
            }
        }
        refreshDetailFromCache()
        warmSnapshots()
        schedulePrefetch()
    }

    private func revalidate(_ key: MonthKey) async throws {
        let range = key.gridRange
        try await fetchRange(range.from, range.to, generation: loadGeneration)
        refreshDetailFromCache()
    }

    /// Loads the neighbours of the visible month in the background. Failures are silent (the visible month is what counts).
    private func schedulePrefetch() {
        prefetchTask?.cancel()
        let key = visibleKey
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            for step in 1...Self.prefetchRadius {
                for neighbour in [key.adding(step), key.adding(-step)] {
                    if Task.isCancelled || self.visibleKey != key { return }
                    guard !self.covers(neighbour) else { continue }
                    let range = neighbour.gridRange
                    try? await self.fetchMissing(range.from, range.to, generation: self.loadGeneration)
                }
            }
            if !Task.isCancelled { self.warmSnapshots() }
        }
    }

    /// Waits for a running prefetch (tests).
    public func waitForPrefetch() async { await prefetchTask?.value }

    private struct Fetched {
        var from: LocalDay
        var to: LocalDay
        var absences: [Absence]
        var plan: [PlanDay]
        var evaluations: [DayEvaluation]
        var holidays: [CalendarDay]
        var years: Set<Int>
    }

    /// Fetches only the parts of `from...to` that the window does not cover yet (at most two pieces next to it).
    private func fetchMissing(_ from: LocalDay, _ to: LocalDay, generation: Int) async throws {
        guard let loaded = loadedRange, isNear(loaded, from, to) else {
            try await fetchRange(from, to, generation: generation)
            return
        }
        if from < loaded.lowerBound, let end = LocalDays.adding(-1, to: loaded.lowerBound) { try await fetchRange(from, min(end, to), generation: generation) }
        if to > loaded.upperBound, let start = LocalDays.adding(1, to: loaded.upperBound) { try await fetchRange(max(start, from), to, generation: generation) }
    }

    private func isNear(_ loaded: ClosedRange<LocalDay>, _ from: LocalDay, _ to: LocalDay) -> Bool {
        let before = LocalDays.daysBetween(to, loaded.lowerBound) ?? 0   // loaded starts after `to`
        let after = LocalDays.daysBetween(loaded.upperBound, from) ?? 0  // `from` starts after loaded ends
        return before <= 1 && after <= 1
    }

    private func fetchRange(_ from: LocalDay, _ to: LocalDay, generation: Int) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let years = Set([from, to].compactMap { LocalDays.parse($0)?.year })
        let newYears = years.subtracting(holidayYears)
        async let absenceResult = client.listAbsences(from: from, to: to)
        async let planResult = client.listPlanDays(from: from, to: to)
        async let evaluationResult = (try? await client.listDays(from: from, to: to)) ?? []
        var loadedHolidays: [CalendarDay] = []
        for year in newYears.sorted() { loadedHolidays += try await client.listHolidays(year: year) }
        let (loadedAbsences, loadedPlan, loadedEvaluations) = try await (absenceResult, planResult, evaluationResult)
        try Task.checkCancellation()
        guard generation == loadGeneration else { return }
        merge(Fetched(from: from, to: to, absences: loadedAbsences, plan: loadedPlan, evaluations: loadedEvaluations, holidays: loadedHolidays, years: newYears))
        let elapsed = clock.now - started
        metrics.rangeFetches += 1
        metrics.requests += 3 + newYears.count
        metrics.lastFetchSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    private func merge(_ fetched: Fetched) {
        let contiguous = loadedRange.map { isNear($0, fetched.from, fetched.to) } ?? false
        if !contiguous {
            // A jump to a distant month starts a new window; the old data would only be a hole-ridden leftover.
            absences = []
            planDays = [:]
            evaluations = [:]
            fetchedAt = [:]
        }
        holidayYears.formUnion(fetched.years)
        holidays += fetched.holidays
        let fetchedIds = Set(fetched.absences.map(\.id))
        let keptAbsences = absences.filter { !fetchedIds.contains($0.id) && !($0.startDate >= fetched.from && $0.endDate <= fetched.to) }
        absences = Self.visible(keptAbsences + fetched.absences)
        var plan = planDays.filter { !($0.key >= fetched.from && $0.key <= fetched.to) }
        for entry in fetched.plan { plan[entry.date] = entry }
        planDays = plan
        evaluations = evaluations.filter { !($0.key >= fetched.from && $0.key <= fetched.to) }
        for evaluation in fetched.evaluations { evaluations[evaluation.date] = evaluation }
        let union = loadedRange.flatMap { contiguous ? min($0.lowerBound, fetched.from)...max($0.upperBound, fetched.to) : nil } ?? fetched.from...fetched.to
        loadedRange = union
        var key = MonthKey(day: fetched.from)
        let last = MonthKey(day: fetched.to)
        while let current = key, let last, current <= last {
            let range = current.gridRange
            if range.from >= fetched.from && range.to <= fetched.to { fetchedAt[current] = .now }
            key = current.adding(1)
        }
    }

    /// Builds the snapshots of the visible month and its neighbours now, so scrolling only reads them.
    private func warmSnapshots() {
        for offset in -Self.prefetchRadius...Self.prefetchRadius { _ = snapshot(for: visibleKey.adding(offset)) }
    }

    /// Render model of one month page. Cached per data version; building it is the only per-month work and happens at load time.
    public func snapshot(for key: MonthKey) -> MonthSnapshot {
        let version = dataVersion
        if let cached = snapshots[key], cached.version == version { return cached.snapshot }
        let clock = ContinuousClock()
        let started = clock.now
        let built = MonthSnapshot.build(key: key, holidays: holidays, absences: absences, planDays: planDays)
        let elapsed = clock.now - started
        metrics.snapshotBuilds += 1
        metrics.lastSnapshotSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        if snapshots.count > 9 { snapshots = snapshots.filter { abs($0.key.index - visibleKey.index) <= 2 } }
        snapshots[key] = (version, built)
        return built
    }

    /// Takes fresher evaluations (e.g. from the week list after an edit) into the window.
    public func mergeEvaluations(_ list: [DayEvaluation]) {
        for evaluation in list { evaluations[evaluation.date] = evaluation }
        refreshDetailFromCache()
    }

    /// Reloads one day (after an entry was created, corrected or voided).
    public func refreshEvaluation(_ day: LocalDay) async {
        guard let fresh = try? await client.getDay(day) else { return }
        evaluations[day] = fresh
        if selectedDay == day { detail = fresh }
    }

    private func refreshDetailFromCache() {
        guard let day = selectedDay, let cached = evaluations[day], cached != detail else { return }
        detail = cached
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
            evaluations[day] = evaluation
            if selectedDay == day { detail = evaluation }
        } catch {
            if selectedDay == day, detail == nil { detail = nil }
        }
    }

    /// Selecting a day answers from the window at once (no empty flash) and refreshes the day in the background.
    public func select(_ day: LocalDay?) async {
        detailTask?.cancel()
        selectedDay = day
        guard let day else {
            detail = nil
            return
        }
        if let cached = evaluations[day] {
            detail = cached
            // Debounced: flicking through months selects many days; only the one that stays is refreshed.
            detailTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await self?.loadDetail()
            }
        } else {
            detail = nil
            await loadDetail()
        }
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
            onOutcome?(.saved)
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
            onOutcome?(.deleted)
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
        planDays[day] = PlanDay(date: day, mode: input.mode, placeId: input.placeId, note: input.note, plannedStart: input.plannedStart,
                                plannedEnd: input.plannedEnd, plannedBreakMinutes: input.plannedBreakMinutes, plannedSeconds: before[day]?.plannedSeconds)
        do {
            planDays[day] = try await client.putPlanDay(day, input)
            error = nil
            onOutcome?(.saved)
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
            onOutcome?(.deleted)
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
            onOutcome?(.saved)
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
            onOutcome?(.deleted)
            return true
        } catch {
            holidays = before
            record(error)
            return false
        }
    }

    /// `notify: false` for reads (a failed load shows the error banner, not a failure haptic).
    private func record(_ failure: Error, notify: Bool = true) {
        if let failure = failure as? TimetrackError {
            if failure != .cancelled {
                error = failure
                if notify { onOutcome?(.failed) }
            }
        } else {
            error = .cancelled
        }
    }
}
