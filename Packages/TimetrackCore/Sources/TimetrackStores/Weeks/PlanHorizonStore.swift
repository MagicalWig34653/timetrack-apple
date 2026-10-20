import Foundation
import Observation
import TimetrackCore

/// State of the multi-week planning overview: the plan totals of the next weeks, loaded in parallel. Read-only; editing happens in
/// the week planner.
@MainActor
@Observable
public final class PlanHorizonStore {
    public enum Entry: Sendable, Hashable, Identifiable {
        case loaded(PlanHorizonRow)
        /// This week could not be loaded (the other weeks still show).
        case failed(monday: LocalDay, isoWeek: String)

        public var id: String {
            switch self {
            case .loaded(let row): row.isoWeek
            case .failed(_, let week): week
            }
        }
    }

    public static let defaultWeeks = 8

    public private(set) var entries: [Entry] = []
    public private(set) var isLoading = false
    /// The server has no plan endpoint (module off or old version): the screen shows a hint.
    public private(set) var isUnavailable = false
    public var error: TimetrackError?

    private let client: APIClient
    public let calendar: DayCalendar
    public let weekCount: Int
    private var generation = 0

    public init(client: APIClient, calendar: DayCalendar, weekCount: Int = PlanHorizonStore.defaultWeeks) {
        self.client = client
        self.calendar = calendar
        self.weekCount = weekCount
    }

    public var today: LocalDay { calendar.day(for: .now) }
    public var currentMonday: LocalDay { LocalDays.mondayOfWeek(containing: today) ?? today }

    /// Weeks with at least one work day still without a plan.
    public var openWeeks: Int {
        entries.reduce(0) { count, entry in
            if case .loaded(let row) = entry, row.coverage != .complete { return count + 1 }
            return count
        }
    }

    public func load() async {
        generation += 1
        let mine = generation
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        let mondays = PlanHorizon.mondays(from: today, count: weekCount)
        let client = client
        let results = await withTaskGroup(of: (Int, Result<PlanWeek, Error>).self) { group in
            for (index, monday) in mondays.enumerated() {
                guard let label = IsoWeek.label(containing: monday) else { continue }
                group.addTask {
                    do { return (index, .success(try await client.getPlanWeek(label))) } catch { return (index, .failure(error)) }
                }
            }
            var collected: [(Int, Result<PlanWeek, Error>)] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }
        }
        guard mine == generation else { return }
        let failures = results.compactMap { item -> TimetrackError? in
            if case .failure(let error) = item.1 { return error as? TimetrackError }
            return nil
        }
        // Every week failed with 404: the plan endpoints do not exist for this account/server.
        if !results.isEmpty, failures.count == results.count, failures.allSatisfy({ $0.status == 404 && $0.knownCode != .moduleDisabled }) {
            isUnavailable = true
            entries = []
            error = nil
            return
        }
        isUnavailable = false
        entries = results.map { index, result in
            switch result {
            case .success(let week): .loaded(PlanHorizon.row(for: week))
            case .failure: .failed(monday: mondays[index], isoWeek: IsoWeek.label(containing: mondays[index]) ?? "")
            }
        }
        error = failures.count == results.count ? failures.first : nil
    }
}
