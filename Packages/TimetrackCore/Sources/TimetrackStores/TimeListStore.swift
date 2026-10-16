import Foundation
import Observation
import TimetrackCore

/// State of the "Zeit" screen: one ISO week of evaluated days with their segments, plus create/correct/void.
@MainActor
@Observable
public final class TimeListStore {
    public private(set) var weekStart: LocalDay
    public private(set) var days: [DayEvaluation] = []
    public private(set) var isLoading = false
    public var error: TimetrackError?

    private let client: APIClient
    public let calendar: DayCalendar

    public init(client: APIClient, calendar: DayCalendar, now: Date = .now) {
        self.client = client
        self.calendar = calendar
        self.weekStart = LocalDays.mondayOfWeek(containing: calendar.day(for: now)) ?? calendar.day(for: now)
    }

    public var weekEnd: LocalDay { LocalDays.adding(6, to: weekStart) ?? weekStart }
    public var weekEvaluatedSeconds: Int { days.reduce(0) { $0 + $1.evaluatedWorkSeconds + $1.creditSeconds } }
    public var weekTargetSeconds: Int { days.reduce(0) { $0 + $1.targetSeconds } }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            days = try await client.listDays(from: weekStart, to: weekEnd).sorted { $0.date < $1.date }
            error = nil
        } catch let failure as TimetrackError {
            if failure != .cancelled { error = failure }
        } catch {
            self.error = .cancelled
        }
    }

    public func shiftWeeks(_ count: Int) async {
        weekStart = LocalDays.adding(7 * count, to: weekStart) ?? weekStart
        await load()
    }

    public func goToCurrentWeek(now: Date = .now) async {
        let today = calendar.day(for: now)
        weekStart = LocalDays.mondayOfWeek(containing: today) ?? today
        await load()
    }

    /// Returns true on success; on failure `error` is set and the list stays unchanged.
    @discardableResult
    public func create(_ input: SegmentInput) async -> Bool {
        await mutate { _ = try await self.client.createSegment(input) }
    }

    @discardableResult
    public func correct(_ segment: Segment, _ correction: SegmentCorrection) async -> Bool {
        await mutate { _ = try await self.client.correctSegment(id: segment.id, correction, ifMatchVersion: segment.version) }
    }

    @discardableResult
    public func void(_ segment: Segment, reason: String) async -> Bool {
        await mutate { try await self.client.voidSegment(id: segment.id, reason: reason) }
    }

    private func mutate(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            error = nil
            await load()
            return true
        } catch let failure as TimetrackError {
            error = failure
        } catch {
            self.error = .cancelled
        }
        return false
    }
}
