import Foundation
import Observation
import TimetrackCore

/// One row of a day section in the "Zeit" list. A section's rows are always ONE collection with stable, unique ids
/// (never a conditional static row next to a `ForEach`), so SwiftUI's `List` diff stays consistent when the last segment disappears.
public enum TimeRow: Identifiable, Hashable, Sendable {
    case empty(day: LocalDay)
    case segment(Segment, day: LocalDay)

    /// `empty-<date>` or `<date>-<segment id>`: unique across the whole list, even if a segment were reported by two days.
    public var id: String {
        switch self {
        case .empty(let day): "empty-\(day)"
        case .segment(let segment, let day): "\(day)-\(segment.id.uuidString)"
        }
    }
}

extension DayEvaluation {
    /// Visible rows of the day: its non-voided segments in start order, or a single empty row.
    public var timeRows: [TimeRow] {
        let visible = (segments ?? []).filter { !$0.voided }.sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
        if visible.isEmpty { return [.empty(day: date)] }
        var seen = Set<UUID>()
        return visible.filter { seen.insert($0.id).inserted }.map { .segment($0, day: date) }
    }
}

/// State of the "Zeit" screen: one ISO week of evaluated days with their segments, plus create/correct/void.
@MainActor
@Observable
public final class TimeListStore {
    public private(set) var weekStart: LocalDay
    public private(set) var days: [DayEvaluation] = []
    public private(set) var isLoading = false
    public var error: TimetrackError?
    /// Reports the result of create/correct/void (never loads).
    public var onOutcome: StoreOutcomeHandler?

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

    private var loadGeneration = 0

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let fresh = try await client.listDays(from: weekStart, to: weekEnd).sorted { $0.date < $1.date }
            // A newer load (or an optimistic change) owns the state; and an unchanged result must not trigger a list update.
            guard generation == loadGeneration else { return }
            if fresh != days { days = fresh }
            error = nil
        } catch let failure as TimetrackError {
            if generation == loadGeneration, failure != .cancelled { error = failure }
        } catch {
            if generation == loadGeneration { self.error = .cancelled }
        }
    }

    public func shiftWeeks(_ count: Int) async {
        weekStart = LocalDays.adding(7 * count, to: weekStart) ?? weekStart
        await load()
    }

    /// Opens the week that contains `day` (the "Zeit" screen follows its anchor day). A no-op reload is skipped.
    public func open(week day: LocalDay) async {
        guard let monday = LocalDays.mondayOfWeek(containing: day), monday != weekStart else { return }
        weekStart = monday
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

    /// Voids on the server, then removes the segment locally in ONE state change and returns, so the caller can dismiss its
    /// sheet before the authoritative reload (which runs afterwards and only touches the list if the result differs).
    @discardableResult
    public func void(_ segment: Segment, reason: String) async -> Bool {
        guard !voidingIds.contains(segment.id) else { return false }
        voidingIds.insert(segment.id)
        defer { voidingIds.remove(segment.id) }
        do {
            try await client.voidSegment(id: segment.id, reason: reason)
        } catch let failure as TimetrackError {
            error = failure
            if failure != .cancelled { onOutcome?(.failed) }
            return false
        } catch {
            self.error = .cancelled
            return false
        }
        error = nil
        onOutcome?(.deleted)
        loadGeneration += 1 // invalidates reloads that started before the void and would bring the segment back
        days = days.map { $0.removingSegment(segment.id) }
        Task { await self.load() }
        return true
    }

    private var voidingIds = Set<UUID>()

    private func mutate(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            error = nil
            onOutcome?(.saved)
            await load()
            return true
        } catch let failure as TimetrackError {
            error = failure
            if failure != .cancelled { onOutcome?(.failed) }
        } catch {
            self.error = .cancelled
        }
        return false
    }
}

extension DayEvaluation {
    /// Copy without the given segment (display only; the next load restores the server's evaluation).
    public func removingSegment(_ id: UUID) -> DayEvaluation {
        guard let segments, segments.contains(where: { $0.id == id }) else { return self }
        return DayEvaluation(copying: self, segments: segments.filter { $0.id != id })
    }
}
