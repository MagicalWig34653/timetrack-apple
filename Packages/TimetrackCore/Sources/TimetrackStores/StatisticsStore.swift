import Foundation
import Observation
import TimetrackCore

/// "Statistik" (WM2): loads `GET /time/statistics` for a range, granularity and basis and derives the chart data.
/// An older server without the endpoint (404) puts the store in `.unsupported`; the screen then explains instead of failing.
@MainActor
@Observable
public final class StatisticsStore {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case ready(StatisticsChartData)
        /// The server does not know the endpoint (contract older than 0.28.0).
        case unsupported
        case failed(TimetrackError)
    }

    public private(set) var state: State = .idle
    public var preset: StatisticsRangePreset = .last3Months
    public var granularity: StatisticsGranularity = .week
    public var basis: StatisticsBasis = .evaluated
    public var customFrom: LocalDay
    public var customTo: LocalDay
    /// Account start (from the last result or the time account); used by the "seit Kontobeginn" preset.
    public private(set) var accountStart: LocalDay?

    private let client: APIClient
    private let calendar: DayCalendar
    private var task: Task<Void, Never>?
    private var generation = 0

    public init(client: APIClient, calendar: DayCalendar, now: @autoclosure () -> Date = .now) {
        self.client = client
        self.calendar = calendar
        let today = calendar.day(for: now())
        customTo = today
        customFrom = LocalDays.adding(-90, to: today) ?? today
    }

    public var today: LocalDay { calendar.day(for: .now) }

    /// The inclusive range the current settings ask for.
    public var range: (from: LocalDay, to: LocalDay) {
        preset.resolve(today: today, accountStart: accountStart, custom: (customFrom, customTo))
    }

    public var rangeDays: Int { (LocalDays.daysBetween(range.from, range.to) ?? 0) + 1 }
    public var allowedGranularities: [StatisticsGranularity] { StatisticsGranularity.allowed(forDays: rangeDays) }

    public var data: StatisticsChartData? {
        if case .ready(let data) = state { return data }
        return nil
    }

    /// Switches the preset and takes its granularity.
    public func select(_ preset: StatisticsRangePreset) {
        self.preset = preset
        if preset != .custom { granularity = preset.defaultGranularity }
        granularity = StatisticsGranularity.resolved(granularity, forDays: rangeDays)
    }

    /// Keeps `granularity` valid after the range changed.
    public func normalizeGranularity() {
        granularity = StatisticsGranularity.resolved(granularity, forDays: rangeDays)
    }

    /// Loads with the current settings; a newer call cancels the pending one.
    public func reload() async {
        task?.cancel()
        if preset == .sinceStart, accountStart == nil { accountStart = (try? await client.getTimeAccount())?.accountStart }
        normalizeGranularity()
        generation += 1
        let mine = generation
        let (from, to) = range
        let (granularity, basis) = (granularity, basis)
        state = .loading
        let work = Task { [client] in
            do {
                let result = try await client.getTimeStatistics(from: from, to: to, granularity: granularity, basis: basis)
                guard !Task.isCancelled, mine == generation else { return }
                accountStart = result.accountStart ?? accountStart
                state = .ready(StatisticsChartData(statistics: result, today: today))
            } catch let failure as TimetrackError {
                guard !Task.isCancelled, mine == generation, failure != .cancelled else { return }
                state = failure.status == 404 && failure.code != APIErrorCode.rangeTooLarge.rawValue ? .unsupported : .failed(failure)
            } catch {
                guard mine == generation else { return }
                state = .failed(.cancelled)
            }
        }
        task = work
        await work.value
    }
}
