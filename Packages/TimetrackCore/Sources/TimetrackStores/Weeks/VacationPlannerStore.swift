import Foundation
import Observation
import TimetrackCore

/// State of the vacation planner (module `planning`, ADR-0025): suggestions from `GET /vacation/suggestions` and booking.
/// The endpoint never changes data; booking is an explicit action that creates planned vacation absences through the absence API.
@MainActor
@Observable
public final class VacationPlannerStore {
    public private(set) var data: VacationSuggestions?
    /// Filters the shown data was fetched with.
    public private(set) var applied: VacationPlannerFilters?
    /// AUD3-B: the absences created by the last `take` (also after a partial result), for "Urlaubsantrag erstellen".
    public private(set) var createdAbsences: [Absence] = []
    public private(set) var isLoading = false
    public private(set) var isUnavailable = false
    public var error: TimetrackError?
    public var filters: VacationPlannerFilters {
        didSet { if filters.isValid { persist() } }
    }
    /// Called once after at least one absence was created, so balance, calendar and the suggestions can reload.
    public var onBooked: (@MainActor () -> Void)?
    /// Reports the result of booking (never loads).
    public var onOutcome: StoreOutcomeHandler?

    private let client: APIClient
    public let calendar: DayCalendar
    private let defaults: UserDefaults?
    private var generation = 0
    static let storageKey = "vacationPlanner.filters"

    public enum TakeResult: Sendable, Equatable {
        case booked(blocks: Int, first: LocalDay, last: LocalDay)
        /// Some blocks were created, then a call failed. The suggestions are reloaded; already created blocks show as booked.
        case partial(done: Int, total: Int, error: TimetrackError)
        case failed(TimetrackError)
        /// Conflicts or a budget overrun were not acknowledged; nothing was sent.
        case needsAcknowledgement
        case nothingToBook
    }

    public init(client: APIClient, calendar: DayCalendar, defaults: UserDefaults? = .standard, now: Date = .now) {
        self.client = client
        self.calendar = calendar
        self.defaults = defaults
        let today = calendar.day(for: now)
        if let defaults, let raw = defaults.data(forKey: Self.storageKey), let stored = try? JSONDecoder().decode(VacationPlannerFilters.self, from: raw) {
            filters = stored.sanitized(today: today)
        } else {
            filters = .defaults(today: today)
        }
    }

    public var today: LocalDay { calendar.day(for: .now) }
    public var budgetYear: Int { data.flatMap { LocalDays.parse($0.from)?.year } ?? LocalDays.parse(today)?.year ?? 0 }
    public var view: (shown: [VacationSuggestion], hidden: Int) {
        guard let data else { return ([], 0) }
        return VacationPlanner.visible(data.suggestions, minEfficiency: filters.minEfficiency, count: filters.count)
    }
    /// The server-side filters were edited since the last request.
    public var isStale: Bool { applied.map { filters.needsFetch(comparedTo: $0) } ?? false }

    private func persist() {
        guard let defaults, let raw = try? JSONEncoder().encode(filters) else { return }
        defaults.set(raw, forKey: Self.storageKey)
    }

    public func load() async {
        guard filters.isValid else { return }
        generation += 1
        let mine = generation
        let used = filters
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        do {
            let result = try await client.getVacationSuggestions(used.query)
            guard mine == generation else { return }
            data = result
            applied = used
            error = nil
            isUnavailable = false
        } catch let failure as TimetrackError {
            guard mine == generation, failure != .cancelled else { return }
            if failure.status == 404, failure.knownCode != .moduleDisabled {
                isUnavailable = true
                data = nil
            } else {
                error = failure
            }
        } catch {
            return
        }
    }

    public func reset() async {
        defaults?.removeObject(forKey: Self.storageKey)
        filters = .defaults(today: today)
        await load()
    }

    /// Books the suggestion as planned vacation: one absence per contiguous block (`VacationPlanner.blocks`). The server counts work days only.
    /// Conflicts and a budget overrun have to be acknowledged by the caller; without it nothing is sent.
    @discardableResult
    public func take(_ suggestion: VacationSuggestion, acknowledgedConflicts: Bool, acknowledgedBudget: Bool) async -> TakeResult {
        let requirements = VacationPlanner.requirements(for: suggestion)
        if (requirements.needsConflictAcknowledgement && !acknowledgedConflicts) || (requirements.exceedsBudget && !acknowledgedBudget) {
            return .needsAcknowledgement
        }
        let blocks = VacationPlanner.blocks(for: suggestion)
        guard let first = blocks.first, let last = blocks.last else { return .nothingToBook }
        var done = 0
        createdAbsences = []
        do {
            for block in blocks {
                let created = try await client.createAbsence(AbsenceInput(kind: .vacation, startDate: block.start, endDate: block.end, status: .planned))
                createdAbsences.append(created)
                done += 1
            }
        } catch {
            let failure = (error as? TimetrackError) ?? .cancelled
            if done > 0 {
                onOutcome?(.failed)
                onBooked?()
                await load()
                return .partial(done: done, total: blocks.count, error: failure)
            }
            if failure != .cancelled { onOutcome?(.failed) }
            return .failed(failure)
        }
        onOutcome?(.saved)
        onBooked?()
        await load()
        return .booked(blocks: blocks.count, first: first.start, last: last.end)
    }
}
