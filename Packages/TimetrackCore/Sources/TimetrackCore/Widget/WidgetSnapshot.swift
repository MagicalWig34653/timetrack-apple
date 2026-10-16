import Foundation

/// Non-secret display state shared between the watch app and its complication through an App Group.
///
/// Security: this type intentionally has no field for the server, the session cookie or any account data.
/// Only what a complication draws is stored: running flag, kind, start date and the finished seconds of today.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public var isRunning: Bool
    public var kind: SegmentKind
    public var startedAt: Date?
    /// Evaluated seconds of today without the running segment (the complication adds the running time itself).
    public var todaySeconds: Int
    /// Calendar day (`yyyy-MM-dd` in the work model's zone) `todaySeconds` belongs to, so a stale total is not shown on the next day.
    public var day: String
    /// Identifier of the work model's zone, used to decide which calendar day it is for the complication.
    public var timeZone: String
    public var updatedAt: Date

    public init(isRunning: Bool, kind: SegmentKind, startedAt: Date?, todaySeconds: Int, day: String, timeZone: String, updatedAt: Date) {
        self.isRunning = isRunning
        self.kind = kind
        self.startedAt = startedAt
        self.todaySeconds = todaySeconds
        self.day = day
        self.timeZone = timeZone
        self.updatedAt = updatedAt
    }

    public static let appGroup = "group.de.linolaske.timetrack"
    public static let empty = WidgetSnapshot(isRunning: false, kind: .work, startedAt: nil, todaySeconds: 0, day: "", timeZone: "Europe/Berlin", updatedAt: .distantPast)

    /// The total is only valid for the day it was written on.
    public func todaySeconds(onDay currentDay: String) -> Int? { day == currentDay ? todaySeconds : nil }

    /// Today's total at `date`, or nil when the snapshot was written on an earlier day.
    public func todaySeconds(at date: Date) -> Int? {
        let zone = TimeZone(identifier: timeZone) ?? .current
        return todaySeconds(onDay: DayCalendar(timeZone: zone).day(for: date))
    }
}

/// Storage for the snapshot. The UserDefaults-backed store uses the App Group suite; tests use a private suite.
public struct WidgetSnapshotStore: Sendable {
    private let suiteName: String?
    private static let key = "widget.snapshot.v1"

    public init(suiteName: String? = WidgetSnapshot.appGroup) { self.suiteName = suiteName }

    private var defaults: UserDefaults? { suiteName.flatMap { UserDefaults(suiteName: $0) } }

    public func read() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: WidgetSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() { defaults?.removeObject(forKey: Self.key) }
}
