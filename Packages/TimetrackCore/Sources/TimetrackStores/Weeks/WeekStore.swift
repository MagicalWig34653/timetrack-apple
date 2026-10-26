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
    public var isCurrentWeek: Bool { LocalDays.mondayOfWeek(containing: today) == monday }

    public func load() async {
        generation += 1
        let mine = generation
        let label = isoWeek
        isLoading = true
        defer { if mine == generation { isLoading = false } }
        do {
            let loaded = try await client.getTimeWeek(label)
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
        monday = moved
        week = nil
        error = nil
        await load()
    }

    public func goToCurrentWeek() async {
        let current = LocalDays.mondayOfWeek(containing: today) ?? today
        guard current != monday else { return await load() }
        monday = current
        week = nil
        error = nil
        await load()
    }

    /// Opens the week that contains `day`.
    public func go(to day: LocalDay) async {
        guard let target = LocalDays.mondayOfWeek(containing: day) else { return }
        monday = target
        week = nil
        error = nil
        await load()
    }
}
