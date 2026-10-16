import Foundation
import Observation
import TimetrackCore

/// State of the read-only "Urlaub" overview (module `planning`): vacation balance and absences of one calendar year.
@MainActor
@Observable
public final class PlanningStore {
    public private(set) var year: Int
    public private(set) var balance: VacationBalance?
    public private(set) var absences: [Absence] = []
    public private(set) var isLoading = false
    public var error: TimetrackError?

    private let client: APIClient

    public init(client: APIClient, calendar: DayCalendar, now: Date = .now) {
        self.client = client
        self.year = LocalDays.parse(calendar.day(for: now))?.year ?? Calendar(identifier: .gregorian).component(.year, from: now)
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let year = year
        do {
            async let balanceResult = client.getVacationBalance(year: year)
            async let absenceResult = client.listAbsences(from: LocalDays.format(year: year, month: 1, day: 1), to: LocalDays.format(year: year, month: 12, day: 31))
            let (loadedBalance, loadedAbsences) = try await (balanceResult, absenceResult)
            guard year == self.year else { return }
            balance = loadedBalance
            absences = loadedAbsences
                .filter { $0.status != .cancelled && $0.status != .rejected }
                .sorted { $0.startDate < $1.startDate }
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {
            self.error = .cancelled
        }
    }

    public func shiftYears(_ count: Int) async {
        year += count
        balance = nil
        absences = []
        await load()
    }
}
