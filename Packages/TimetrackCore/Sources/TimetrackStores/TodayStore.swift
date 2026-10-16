import Foundation
import Observation
import TimetrackCore

/// State of the "Heute" screen: running timer, today's evaluated day and the time account balance.
/// All numbers come from the backend; this store only starts/stops the timer and displays results.
@MainActor
@Observable
public final class TodayStore {
    public private(set) var running: Segment?
    public private(set) var day: DayEvaluation?
    public private(set) var account: TimeAccount?
    public private(set) var segments: [Segment] = []
    public private(set) var isLoading = false
    public var error: TimetrackError?

    private let client: APIClient
    private let calendar: DayCalendar

    public init(client: APIClient, calendar: DayCalendar) {
        self.client = client
        self.calendar = calendar
    }

    public var todayLabel: LocalDay { calendar.day(for: .now) }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let today = calendar.day(for: .now)
        do {
            async let timer = client.currentTimer()
            async let evaluation = client.getDay(today)
            async let balance = client.getTimeAccount(asOf: today)
            let (timerValue, dayValue, accountValue) = try await (timer, evaluation, balance)
            running = timerValue
            day = dayValue
            account = accountValue
            segments = (dayValue.segments ?? []).filter { !$0.voided }.sorted { $0.startedAt < $1.startedAt }
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {
            self.error = .cancelled
        }
    }

    public func start(kind: SegmentKind = .work) async {
        let eventId = UUID()
        let client = client
        await perform {
            let segment = try await retryOnNetworkError { try await client.startTimer(clientEventId: eventId, kind: kind) }
            self.running = segment
        }
    }

    public func stop() async {
        let eventId = UUID()
        let client = client
        await perform {
            _ = try await retryOnNetworkError { try await client.stopTimer(clientEventId: eventId) }
            self.running = nil
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        var failure: TimetrackError?
        do {
            try await action()
        } catch let thrown as TimetrackError {
            failure = thrown
        } catch {
            failure = .cancelled
        }
        await load()
        if let failure { error = failure }
    }
}
