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
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var isUnavailable = false
    /// Set after a save attempt with invalid rows so the screen marks them.
    public private(set) var showProblems = false
    public var error: TimetrackError?
    /// Reports the result of saving (never loads).
    public var onOutcome: StoreOutcomeHandler?
    /// Called after a successful save so other screens (calendar, week overview) can reload.
    public var onSaved: (@MainActor () -> Void)?

    private let client: APIClient
    public let calendar: DayCalendar
    private var generation = 0

    public enum CopyResult: Sendable, Equatable { case copied, emptySource, failed }

    /// Without `initialMonday` the planner opens next week: planning is for weeks that have not started yet.
    public init(client: APIClient, calendar: DayCalendar, initialMonday: LocalDay? = nil, now: Date = .now) {
        self.client = client
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
            let loaded = try await client.getPlanWeek(label)
            let typical = loaded.days.map(\.targetSeconds).max() ?? 0
            let suggested = await historySuggestion(before: reference, targetSeconds: typical)
            guard mine == generation else { return }
            week = loaded
            drafts = loaded.days.map(WeekPlan.draft(from:))
            baseline = drafts
            suggestion = suggested
            error = nil
            isUnavailable = false
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

    public func open(monday target: LocalDay) async {
        monday = LocalDays.mondayOfWeek(containing: target) ?? target
        week = nil
        drafts = []
        baseline = []
        error = nil
        await load()
    }

    // MARK: Editing

    public func update(_ index: Int, _ draft: DayDraft) {
        guard drafts.indices.contains(index) else { return }
        drafts[index] = draft
    }

    public func setMode(_ index: Int, _ mode: PlanMode?) {
        guard drafts.indices.contains(index), days.indices.contains(index) else { return }
        drafts[index] = WeekPlan.withMode(drafts[index], mode, suggestion: suggestion, targetSeconds: days[index].targetSeconds)
    }

    public func applyStandard() { drafts = WeekPlan.standardWeek(days: days, current: drafts, suggestion: suggestion) }
    public func applySame() { drafts = WeekPlan.sameForWorkdays(days: days, current: drafts) }
    public func applyClear() { drafts = WeekPlan.clearWeek(days: days, current: drafts) }

    public func discard() {
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
            drafts = WeekPlan.copyWeek(source: source, days: days, current: drafts)
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
        defer { isSaving = false }
        do {
            let saved = try await client.putPlanWeek(isoWeek, WeekPlan.request(drafts))
            week = saved
            drafts = saved.days.map(WeekPlan.draft(from:))
            baseline = drafts
            showProblems = false
            onOutcome?(.saved)
            onSaved?()
            return true
        } catch {
            if let failure = error as? TimetrackError, failure != .cancelled {
                self.error = failure
                onOutcome?(.failed)
            }
            return false
        }
    }
}
