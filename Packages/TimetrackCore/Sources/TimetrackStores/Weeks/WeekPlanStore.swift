import Foundation
import Observation
import TimetrackCore

/// State of the week planner (module `planning`): a draft per day, edited locally and saved in one `PUT /plan/weeks/{isoWeek}`.
/// A plan never books time; saving it changes no evaluation.
@MainActor
@Observable
public final class WeekPlanStore {
    public private(set) var monday: LocalDay
    public private(set) var week: PlanWeek?
    public private(set) var drafts: [DayDraft] = []
    public private(set) var baseline: [DayDraft] = []
    public private(set) var suggestion = WeekPlan.fallbackWindow(targetSeconds: 27_720)
    /// AUD3-B: holiday / company day names of the shown week (best effort; empty when the calendar cannot be read).
    public private(set) var holidayNotes: [LocalDay: HolidayNote] = [:]
    @ObservationIgnored private var holidayYears: [Int: [CalendarDay]] = [:]
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var isUnavailable = false
    /// Set after a save attempt with invalid rows so the screen marks them.
    public private(set) var showProblems = false
    public var error: TimetrackError?
    /// P13: the server accepts and returns plan blocks (API 0.35.0). Without it the planner keeps the old single window per day.
    public private(set) var supportsBlocks = false
    private var capabilityKnown = false
    /// U2: undo history of the draft list (snapshots before each edit; the baseline is never touched).
    public private(set) var undoStack: [[DayDraft]] = []
    public private(set) var redoStack: [[DayDraft]] = []
    public static let undoLimit = 50
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// Reports the result of saving (never loads).
    public var onOutcome: StoreOutcomeHandler?
    /// Called after a successful save so other screens (calendar, week overview) can reload.
    public var onSaved: (@MainActor () -> Void)?

    private let client: APIClient
    public let calendar: DayCalendar
    private var generation = 0
    /// Bumped whenever another week is opened; a save that finishes under a different epoch must not touch the visible week.
    private var weekEpoch = 0
    /// Week switch requested while a save was running; performed after a successful save, dropped after a failed one.
    private var pendingOpen: LocalDay?

    public enum CopyResult: Sendable, Equatable { case copied, emptySource, failed }

    /// Without `initialMonday` the planner opens next week: planning is for weeks that have not started yet.
    public init(client: APIClient, calendar: DayCalendar, initialMonday: LocalDay? = nil, now: Date = .now, supportsBlocks: Bool? = nil) {
        self.client = client
        if let supportsBlocks {
            self.supportsBlocks = supportsBlocks
            capabilityKnown = true
        }
        self.calendar = calendar
        let today = calendar.day(for: now)
        let current = LocalDays.mondayOfWeek(containing: today) ?? today
        self.monday = initialMonday ?? LocalDays.adding(7, to: current) ?? current
    }

    // MARK: Derived

    public var today: LocalDay { calendar.day(for: .now) }
    public var currentMonday: LocalDay { LocalDays.mondayOfWeek(containing: today) ?? today }
    public var sunday: LocalDay { LocalDays.adding(6, to: monday) ?? monday }
    public var isoWeek: String { IsoWeek.label(containing: monday) ?? "" }
    public var weekNumber: Int { IsoWeek.number(of: isoWeek) ?? 0 }
    public var days: [PlanWeekDay] { week?.days ?? [] }
    public var isDirty: Bool { week != nil && drafts != baseline }
    public var totals: PlanWeekTotals { WeekPlan.totals(days: days, drafts: drafts) }
    public var isPast: Bool { sunday < today }

    public func problem(at index: Int) -> DraftProblem? {
        guard drafts.indices.contains(index), days.indices.contains(index), !days[index].isBlocked else { return nil }
        return WeekPlan.problem(drafts[index])
    }

    public var hasProblem: Bool { drafts.indices.contains { problem(at: $0) != nil } }

    // MARK: Loading

    public func load() async {
        generation += 1
        let mine = generation
        let label = isoWeek
        let reference = monday
        isLoading = true
        showProblems = false
        defer { if mine == generation { isLoading = false } }
        do {
            await resolveCapability()
            let loaded = try await client.getPlanWeek(label)
            let typical = loaded.days.map(\.targetSeconds).max() ?? 0
            let suggested = await historySuggestion(before: reference, targetSeconds: typical)
            guard mine == generation else { return }
            week = loaded
            drafts = loaded.days.map { WeekPlan.draft(from: $0, multi: supportsBlocks) }
            baseline = drafts
            clearHistory()
            suggestion = suggested
            error = nil
            isUnavailable = false
            await loadHolidayNotes(monday: reference, generation: mine)
        } catch let failure as TimetrackError {
            guard mine == generation, failure != .cancelled else { return }
            if failure.status == 404, failure.knownCode != .moduleDisabled {
                isUnavailable = true
                week = nil
            } else {
                error = failure
            }
        } catch {
            return
        }
    }

    /// Reads the backend's `apiVersion` once (a failure keeps the old single-window planner and is retried on the next load).
    private func resolveCapability() async {
        guard !capabilityKnown else { return }
        guard let info = try? await client.getSystemInfo() else { return }
        supportsBlocks = PlanBlocks.isSupported(apiVersion: info.backend.apiVersion)
        capabilityKnown = true
    }

    /// Average start/end of the four completed weeks before the planned week (or before this week for future weeks).
    private func historySuggestion(before reference: LocalDay, targetSeconds: Int) async -> WindowSuggestion {
        let reach = min(reference, currentMonday)
        let labels = (1...4).compactMap { back in LocalDays.adding(-7 * back, to: reach).flatMap { IsoWeek.label(containing: $0) } }
        let client = client
        let summaries = await withTaskGroup(of: TimeWeekSummary?.self) { group in
            for label in labels { group.addTask { try? await client.getTimeWeek(label).summary } }
            var result: [TimeWeekSummary] = []
            for await summary in group { if let summary { result.append(summary) } }
            return result
        }
        return WeekPlan.suggestWindow(history: summaries, targetSeconds: targetSeconds)
    }

    /// Switches week and drops the drafts; the caller asks for confirmation first when `isDirty`.
    public func shiftWeeks(_ count: Int) async {
        guard let moved = LocalDays.adding(7 * count, to: monday) else { return }
        await open(monday: moved)
    }

    /// Reads the years the week touches (cached per year) and derives the day notes; a failure leaves the planner as before.
    private func loadHolidayNotes(monday reference: LocalDay, generation mine: Int) async {
        let sundayOfWeek = LocalDays.adding(6, to: reference) ?? reference
        let years = Set([LocalDays.parse(reference)?.year, LocalDays.parse(sundayOfWeek)?.year].compactMap { $0 })
        for year in years where holidayYears[year] == nil {
            if let list = try? await client.listHolidays(year: year) { holidayYears[year] = list }
        }
        guard mine == generation else { return }
        holidayNotes = HolidayNote.notes(from: reference, in: years.flatMap { holidayYears[$0] ?? [] })
    }

    public func open(monday target: LocalDay) async {
        // Never switch weeks under a running PUT: queue the switch, `save()` performs it afterwards.
        if isSaving {
            pendingOpen = LocalDays.mondayOfWeek(containing: target) ?? target
            return
        }
        weekEpoch += 1
        monday = LocalDays.mondayOfWeek(containing: target) ?? target
        week = nil
        holidayNotes = [:]
        drafts = []
        baseline = []
        error = nil
        await load()
    }

    // MARK: Editing

    /// Block operations of one day (P13). Every operation keeps the list ordered; the mode of the day is not changed.
    public func addBlock(_ index: Int, kind: PlanBlockKind? = nil) {
        guard supportsBlocks, drafts.indices.contains(index), let mode = drafts[index].mode, mode != .off else { return }
        drafts[index].blocks = PlanBlockEditing.adding(to: drafts[index].blocks, kind: kind ?? WeekPlan.defaultKind(for: mode))
    }

    public func splitBlock(_ index: Int, at block: Int) {
        guard drafts.indices.contains(index) else { return }
        drafts[index].blocks = PlanBlockEditing.splitting(drafts[index].blocks, at: block)
    }

    public func deleteBlock(_ index: Int, at block: Int) {
        guard drafts.indices.contains(index) else { return }
        drafts[index].blocks = PlanBlockEditing.deleting(drafts[index].blocks, at: block)
    }

    public func mergeBlock(_ index: Int, at block: Int) {
        guard drafts.indices.contains(index) else { return }
        drafts[index].blocks = PlanBlockEditing.mergingWithNext(drafts[index].blocks, at: block)
    }

    public func updateBlock(_ index: Int, at block: Int, _ change: (inout PlanTimeBlock) -> Void) {
        guard drafts.indices.contains(index), drafts[index].blocks.indices.contains(block) else { return }
        change(&drafts[index].blocks[block])
    }

    /// Live hints of a day: from the draft while editing (same rule as the server).
    public func hints(at index: Int) -> [PlanHint] {
        guard drafts.indices.contains(index) else { return [] }
        return WeekPlan.hints(drafts[index])
    }

    public func update(_ index: Int, _ draft: DayDraft) {
        guard drafts.indices.contains(index) else { return }
        drafts[index] = draft
    }

    public func setMode(_ index: Int, _ mode: PlanMode?) {
        guard drafts.indices.contains(index), days.indices.contains(index) else { return }
        record()
        drafts[index] = WeekPlan.withMode(drafts[index], mode, suggestion: suggestion, targetSeconds: days[index].targetSeconds, multi: supportsBlocks)
    }

    // MARK: U2 history and grid edits

    private func clearHistory() { undoStack = []; redoStack = [] }

    /// Remembers the current drafts before an edit (one entry per user action, also for a whole drag).
    public func record() {
        guard undoStack.last != drafts else { return }
        undoStack.append(drafts)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack = []
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(drafts)
        drafts = previous
        showProblems = false
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(drafts)
        drafts = next
    }

    private func editable(_ index: Int) -> Bool { drafts.indices.contains(index) && days.indices.contains(index) && !days[index].isBlocked }

    /// Paints a block into day `index` (the new block wins over what it covers). Returns the index of the new block, nil when refused.
    @discardableResult
    public func paintBlock(_ index: Int, range: MinuteRange, kind: PlanBlockKind, placeId: UUID? = nil) -> Int? {
        guard supportsBlocks, editable(index), let placed = PlanGridEdit.paint(drafts[index], range: range, kind: kind, placeId: placeId) else { return nil }
        record()
        drafts[index] = placed.draft
        return placed.index
    }

    /// Moves a block (possibly to another day); returns its new index in the target day.
    @discardableResult
    public func moveBlock(from index: Int, at block: Int, toDay target: Int, range: MinuteRange) -> Int? {
        guard supportsBlocks, editable(index), editable(target), drafts[index].blocks.indices.contains(block) else { return nil }
        if index == target {
            guard let placed = PlanGridEdit.move(drafts[index], at: block, to: range) else { return nil }
            record()
            drafts[index] = placed.draft
            return placed.index
        }
        var moved = drafts[index].blocks[block]
        moved.start = WeekPlan.formatClock(range.start)
        moved.end = WeekPlan.formatClock(range.end)
        guard let placed = PlanGridEdit.place(drafts[target], block: moved) else { return nil }
        record()
        drafts[target] = placed.draft
        drafts[index] = PlanGridEdit.erase(drafts[index], at: block)
        return placed.index
    }

    public func resizeBlock(_ index: Int, at block: Int, edge: PlanGrid.Edge, to minute: Int, step: Int = PlanGrid.snapMinutes) {
        guard editable(index), let resized = PlanGridEdit.resize(drafts[index], at: block, edge: edge, to: minute, step: step), resized != drafts[index] else { return }
        record()
        drafts[index] = resized
    }

    public func eraseBlock(_ index: Int, at block: Int) {
        guard editable(index), drafts[index].blocks.indices.contains(block) else { return }
        record()
        drafts[index] = PlanGridEdit.erase(drafts[index], at: block)
    }

    /// Changes kind, place and note of one block as one undo step.
    public func setBlockDetails(_ index: Int, at block: Int, kind: PlanBlockKind, placeId: UUID?, note: String?) {
        guard editable(index), drafts[index].blocks.indices.contains(block) else { return }
        record()
        drafts[index].blocks[block].kind = kind
        drafts[index].blocks[block].placeId = placeId
        let trimmed = note.map { String($0.prefix(PlanBlocks.maxNoteLength)) }
        drafts[index].blocks[block].note = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Copies the plan of day `source` onto the given other days (blocked days are skipped); returns the days that took it.
    @discardableResult
    public func copyDay(_ source: Int, to targets: [Int]) -> [Int] {
        guard drafts.indices.contains(source) else { return [] }
        let accepted = targets.filter { $0 != source && editable($0) }
        guard !accepted.isEmpty else { return [] }
        record()
        for target in accepted { drafts[target] = PlanGridEdit.copy(drafts[source], to: drafts[target].date) }
        return accepted
    }

    public func applyStandard() { record(); drafts = WeekPlan.standardWeek(days: days, current: drafts, suggestion: suggestion, multi: supportsBlocks) }
    public func applySame() { record(); drafts = WeekPlan.sameForWorkdays(days: days, current: drafts) }
    public func applyClear() { record(); drafts = WeekPlan.clearWeek(days: days, current: drafts) }

    public func discard() {
        clearHistory()
        drafts = baseline
        showProblems = false
        error = nil
    }

    /// Copies the plan of the week before day by day. Nothing changes when that week has no plan.
    public func copyLastWeek() async -> CopyResult {
        guard let previous = LocalDays.adding(-7, to: monday).flatMap({ IsoWeek.label(containing: $0) }) else { return .failed }
        do {
            let source = try await client.getPlanWeek(previous)
            guard source.days.contains(where: { $0.plan != nil }) else { return .emptySource }
            record()
            drafts = WeekPlan.copyWeek(source: source, days: days, current: drafts, multi: supportsBlocks)
            error = nil
            return .copied
        } catch {
            if let failure = error as? TimetrackError, failure != .cancelled { self.error = failure }
            return .failed
        }
    }

    // MARK: Saving

    @discardableResult
    public func save() async -> Bool {
        guard !isSaving, week != nil else { return false }
        error = nil
        if hasProblem {
            showProblems = true
            return false
        }
        isSaving = true
        // Remember what was sent and for which week: the response only applies if the same week is still shown.
        let sent = drafts
        let epoch = weekEpoch
        let label = isoWeek
        let succeeded: Bool
        do {
            let saved = try await client.putPlanWeek(label, WeekPlan.request(sent, multi: supportsBlocks))
            if epoch == weekEpoch {
                week = saved
                let serverDrafts = saved.days.map { WeekPlan.draft(from: $0, multi: supportsBlocks) }
                // Edits made while the PUT ran stay in the drafts (and the plan stays unsaved); only the baseline moves.
                if drafts == sent { drafts = serverDrafts }
                baseline = serverDrafts
                clearHistory()
                showProblems = false
            }
            onOutcome?(.saved)
            onSaved?()
            succeeded = true
        } catch {
            if let failure = error as? TimetrackError, failure != .cancelled {
                self.error = failure
                onOutcome?(.failed)
            }
            succeeded = false
        }
        isSaving = false
        let queued = pendingOpen
        pendingOpen = nil
        if succeeded, let queued, queued != monday { await open(monday: queued) }
        return succeeded
    }
}
