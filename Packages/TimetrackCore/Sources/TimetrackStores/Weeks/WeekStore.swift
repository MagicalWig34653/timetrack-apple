import Foundation
import Observation
import TimetrackCore

/// State of the week overview ("Woche"): one ISO week from `GET /time/weeks/{isoWeek}`. Read-only, no module needed.
@MainActor
@Observable
public final class WeekStore {
    public private(set) var monday: LocalDay
    public private(set) var week: TimeWeek?
    public private(set) var isLoading = false
    /// The server does not know the endpoint (older version): the screen shows a hint instead of an error.
    public private(set) var isUnavailable = false
    public var error: TimetrackError?

    private let client: APIClient
    public let calendar: DayCalendar
    private var generation = 0
    /// Weeks seen so far (stale-while-revalidate, like the PWA W3): shown immediately on a switch, always revalidated by `load()`.
    private var cache: [String: TimeWeek] = [:]
    private var cacheOrder: [String] = []
    private static let cacheLimit = 8
    private let clock: () -> Date

    public init(client: APIClient, calendar: DayCalendar, now: Date? = nil) {
        self.client = client
        self.calendar = calendar
        self.clock = { now ?? .now }
        let today = calendar.day(for: clock())
        self.monday = LocalDays.mondayOfWeek(containing: today) ?? today
    }

    public var today: LocalDay { calendar.day(for: clock()) }
    public var sunday: LocalDay { LocalDays.adding(6, to: monday) ?? monday }
    public var isoWeek: String { IsoWeek.label(containing: monday) ?? "" }
    public var weekNumber: Int { IsoWeek.number(of: isoWeek) ?? LocalDays.isoWeek(of: monday) ?? 0 }
    /// True while the shown `week` belongs to another ISO week than `monday` (previous week kept visible during the switch).
    public var isStale: Bool { week != nil && week?.week != isoWeek }
    public var isCurrentWeek: Bool { LocalDays.mondayOfWeek(containing: today) == monday }

    public func load() async {
        generation += 1
        let mine = generation
        let label = isoWeek
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        do {
            let loaded = try await client.getTimeWeek(label)
            remember(loaded)
            guard mine == generation else { return }
            week = loaded
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

    public func shiftWeeks(_ count: Int) async {
        guard let moved = LocalDays.adding(7 * count, to: monday) else { return }
        await switchTo(moved, prefetching: count)
    }

    public func goToCurrentWeek() async {
        let current = LocalDays.mondayOfWeek(containing: today) ?? today
        guard current != monday else { return await load() }
        await switchTo(current, prefetching: 0)
    }

    /// Opens the week that contains `day`.
    public func go(to day: LocalDay) async {
        guard let target = LocalDays.mondayOfWeek(containing: day) else { return }
        await switchTo(target, prefetching: 0)
    }

    /// Switches to `target` without emptying the screen: a cached week is shown at once, otherwise the previous week stays visible
    /// (marked `isStale`) until the load answers. An unavailable endpoint is the only case that clears it.
    private func switchTo(_ target: LocalDay, prefetching direction: Int) async {
        monday = target
        if let cached = cache[isoWeek] { week = cached }
        error = nil
        await load()
        guard direction != 0, let next = LocalDays.adding(7 * (direction > 0 ? 1 : -1), to: target).flatMap({ IsoWeek.label(containing: $0) }) else { return }
        await prefetch(next)
    }

    /// Cheap read-ahead of the neighbor in swipe direction; failures are ignored.
    private func prefetch(_ label: String) async {
        guard cache[label] == nil, !isUnavailable, let loaded = try? await client.getTimeWeek(label) else { return }
        remember(loaded)
    }

    private func remember(_ loaded: TimeWeek) {
        cache[loaded.week] = loaded
        cacheOrder.removeAll { $0 == loaded.week }
        cacheOrder.append(loaded.week)
        while cacheOrder.count > Self.cacheLimit { cache[cacheOrder.removeFirst()] = nil }
    }
}
