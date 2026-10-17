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
    /// Added for the Home Screen widgets (all optional, so older snapshots still decode): today's target in seconds.
    public var targetSeconds: Int?
    /// Time account balance in seconds as of today.
    public var balanceSeconds: Int?
    /// Finished and running segments of `day` in start order (capped at `maxSegments`); no notes, places or ids.
    public var segments: [WidgetSegment]?
    /// Added with the account-level appearance (A8, optional): the effective base accent `#RRGGBB` and the colour scheme id
    /// (`system|light|dark`). Widgets derive fill/ink from the hex with `AccentDerivation`; the scheme is informational
    /// (widgets follow the system appearance). No account data, nothing secret.
    public var accentHex: String?
    public var colorScheme: String?

    public static let maxSegments = 8

    public init(isRunning: Bool, kind: SegmentKind, startedAt: Date?, todaySeconds: Int, day: String, timeZone: String, updatedAt: Date,
                targetSeconds: Int? = nil, balanceSeconds: Int? = nil, segments: [WidgetSegment]? = nil,
                accentHex: String? = nil, colorScheme: String? = nil) {
        self.accentHex = accentHex.flatMap(Preferences.normalizedHex)
        self.colorScheme = colorScheme.flatMap { ColorSchemePreference(rawValue: $0)?.rawValue }
        self.targetSeconds = targetSeconds
        self.balanceSeconds = balanceSeconds
        self.segments = segments.map { Array($0.suffix(Self.maxSegments)) }
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

    /// Builds the snapshot from what the app currently shows. `todaySeconds` is evaluated work plus credits (as on the Heute screen).
    public static func make(running: Segment?, day: DayEvaluation?, account: TimeAccount?, segments: [Segment], zone: TimeZone, now: Date = .now,
                            accentHex: String? = nil, colorScheme: String? = nil) -> WidgetSnapshot {
        let calendar = DayCalendar(timeZone: zone)
        let ordered = segments.filter { !$0.voided }.sorted { $0.startedAt < $1.startedAt }
        return WidgetSnapshot(
            isRunning: running != nil, kind: running?.kind ?? .work, startedAt: running?.startedAt,
            todaySeconds: (day?.evaluatedWorkSeconds ?? 0) + (day?.creditSeconds ?? 0),
            day: calendar.day(for: now), timeZone: zone.identifier, updatedAt: now,
            targetSeconds: day?.targetSeconds, balanceSeconds: account?.balanceSeconds,
            segments: ordered.map { WidgetSegment(kind: $0.kind, startedAt: $0.startedAt, endedAt: $0.endedAt) },
            accentHex: accentHex, colorScheme: colorScheme
        )
    }

    /// Snapshot of what a compact screen shows (live data plus queued actions), for the complication and the next launch.
    public static func make(display: TodayDisplay, zone: TimeZone, now: Date = .now, accentHex: String? = nil, colorScheme: String? = nil) -> WidgetSnapshot {
        WidgetSnapshot(
            isRunning: display.isRunning, kind: display.kind, startedAt: display.startedAt, todaySeconds: display.doneSeconds,
            day: DayCalendar(timeZone: zone).day(for: now), timeZone: zone.identifier, updatedAt: now,
            targetSeconds: display.targetSeconds, balanceSeconds: display.balanceSeconds, segments: display.segments,
            accentHex: accentHex, colorScheme: colorScheme
        )
    }

    /// Equal apart from the update time (used to skip needless writes and complication reloads).
    public func sameContent(as other: WidgetSnapshot) -> Bool {
        var copy = other
        copy.updatedAt = updatedAt
        return self == copy
    }

    /// True when the snapshot is older than `maxAge` seconds at `date` (the widget then shows "Aktualisiert um ...").
    public func isStale(at date: Date, maxAge: TimeInterval = 30 * 60) -> Bool { date.timeIntervalSince(updatedAt) > maxAge }

    /// Segments of today only (a snapshot from an earlier day shows none).
    public func segments(at date: Date) -> [WidgetSegment] {
        todaySeconds(at: date) == nil ? [] : (segments ?? [])
    }

    /// The total is only valid for the day it was written on.
    public func todaySeconds(onDay currentDay: String) -> Int? { day == currentDay ? todaySeconds : nil }

    /// Today's total at `date`, or nil when the snapshot was written on an earlier day.
    public func todaySeconds(at date: Date) -> Int? {
        let zone = TimeZone(identifier: timeZone) ?? .current
        return todaySeconds(onDay: DayCalendar(timeZone: zone).day(for: date))
    }
}

/// One segment as shown in the large widget: kind and times only.
public struct WidgetSegment: Codable, Sendable, Equatable, Hashable {
    public var kind: SegmentKind
    public var startedAt: Date
    public var endedAt: Date?

    public init(kind: SegmentKind, startedAt: Date, endedAt: Date?) {
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
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
