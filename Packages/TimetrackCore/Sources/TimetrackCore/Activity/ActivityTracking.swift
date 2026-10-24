import Foundation

// M2: local, opt-in activity capture on the Mac ("Aktivitätserfassung").
//
// Which app is in the foreground while a timer runs. Everything here is pure value logic; the Mac app feeds it with
// NSWorkspace notifications. Nothing in this file (or its callers) sends data to the server: the log lives in the app
// container, and the only way a result reaches the account is an editable suggestion that the user accepts.

/// User settings of the activity capture. Everything is off by default; window titles are a separate, second opt-in.
public struct ActivitySettings: Codable, Sendable, Hashable {
    /// Master switch. Off: nothing is observed and nothing is stored.
    public var enabled: Bool
    /// Only record while a timer runs (default). Off: record whenever the Mac is in use (still not when locked, asleep or idle).
    public var onlyWhileTimerRuns: Bool
    /// Also record the title of the focused window. Needs the Accessibility permission and is off by default.
    public var recordWindowTitles: Bool
    /// Temporary pause: keeps the data, records nothing.
    public var paused: Bool
    /// Intervals older than this are deleted automatically.
    public var retentionDays: Int
    /// Apps that are never recorded (bundle identifiers).
    public var excludedBundleIDs: [String]

    public static let retentionOptions = [1, 7, 14, 30, 90]
    public static let defaultRetentionDays = 14

    public init(enabled: Bool = false, onlyWhileTimerRuns: Bool = true, recordWindowTitles: Bool = false, paused: Bool = false,
                retentionDays: Int = ActivitySettings.defaultRetentionDays, excludedBundleIDs: [String] = []) {
        self.enabled = enabled
        self.onlyWhileTimerRuns = onlyWhileTimerRuns
        self.recordWindowTitles = recordWindowTitles
        self.paused = paused
        self.retentionDays = retentionDays
        self.excludedBundleIDs = excludedBundleIDs
    }

    private enum CodingKeys: String, CodingKey { case enabled, onlyWhileTimerRuns, recordWindowTitles, paused, retentionDays, excludedBundleIDs }

    /// Tolerant decoding: missing keys fall back to the privacy-friendly defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        onlyWhileTimerRuns = try container.decodeIfPresent(Bool.self, forKey: .onlyWhileTimerRuns) ?? true
        recordWindowTitles = try container.decodeIfPresent(Bool.self, forKey: .recordWindowTitles) ?? false
        paused = try container.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? Self.defaultRetentionDays
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? []
    }

    public var clamped: ActivitySettings {
        var copy = self
        copy.retentionDays = min(max(retentionDays, 1), 365)
        copy.excludedBundleIDs = Array(Set(excludedBundleIDs)).sorted()
        return copy
    }

    /// True while the recorder may observe at all (the timer, lock and idle conditions come on top).
    public var isRecording: Bool { enabled && !paused }

    public func isExcluded(_ bundleID: String) -> Bool { excludedBundleIDs.contains(bundleID) }
}

/// One stretch of time in which one app was in the foreground.
public struct ActivityInterval: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var bundleID: String
    public var appName: String
    public var start: Date
    public var end: Date
    /// Only set when the user enabled window titles.
    public var windowTitle: String?

    public init(id: UUID = UUID(), bundleID: String, appName: String, start: Date, end: Date, windowTitle: String? = nil) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.start = start
        self.end = end
        self.windowTitle = windowTitle
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// What the Mac reports about the foreground right now.
public struct ForegroundApp: Sendable, Hashable {
    public var bundleID: String
    public var appName: String
    public var windowTitle: String?

    public init(bundleID: String, appName: String, windowTitle: String? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

/// The conditions that, besides the user's settings, decide whether anything is recorded at an instant.
public struct ActivityContext: Sendable, Hashable {
    public var timerRunning: Bool
    public var screenLocked: Bool
    public var asleep: Bool
    public var idle: Bool

    public init(timerRunning: Bool, screenLocked: Bool = false, asleep: Bool = false, idle: Bool = false) {
        self.timerRunning = timerRunning
        self.screenLocked = screenLocked
        self.asleep = asleep
        self.idle = idle
    }
}

/// State machine behind the capture: turns "app X is in front at time t" observations into closed intervals.
///
/// The caller reports every change (foreground app, timer, lock, sleep, idle, settings) with `update` and calls it periodically
/// with `checkpoint` so that a crash loses at most a minute. A closed interval shorter than `minimumSeconds` is dropped
/// (switching through apps with Cmd-Tab is not use).
public struct ActivityRecorder: Sendable {
    public static let minimumSeconds: TimeInterval = 3

    public private(set) var open: ActivityInterval?

    public init() {}

    /// Applies one observation. Returns the intervals closed by it (zero or one).
    public mutating func update(foreground: ForegroundApp?, at now: Date, context: ActivityContext, settings: ActivitySettings) -> [ActivityInterval] {
        guard let foreground, Self.allowed(foreground, context: context, settings: settings) else { return close(at: now) }
        let title = settings.recordWindowTitles ? foreground.windowTitle.flatMap(Self.cleanTitle) : nil
        if let open, open.bundleID == foreground.bundleID, open.windowTitle == title { return [] }
        let closed = close(at: now)
        open = ActivityInterval(bundleID: foreground.bundleID, appName: foreground.appName, start: now, end: now, windowTitle: title)
        return closed
    }

    /// Closes the open interval at `now` and opens an identical one that continues from there (periodic save).
    public mutating func checkpoint(at now: Date) -> [ActivityInterval] {
        guard let current = open else { return [] }
        let closed = close(at: now)
        open = ActivityInterval(bundleID: current.bundleID, appName: current.appName, start: now, end: now, windowTitle: current.windowTitle)
        return closed
    }

    /// Ends the capture (app quits, switched off).
    public mutating func finish(at now: Date) -> [ActivityInterval] { close(at: now) }

    private mutating func close(at now: Date) -> [ActivityInterval] {
        guard var interval = open else { return [] }
        open = nil
        interval.end = max(now, interval.start)
        return interval.duration >= Self.minimumSeconds ? [interval] : []
    }

    static func allowed(_ foreground: ForegroundApp, context: ActivityContext, settings: ActivitySettings) -> Bool {
        guard settings.isRecording, !settings.isExcluded(foreground.bundleID) else { return false }
        guard !context.screenLocked, !context.asleep, !context.idle else { return false }
        return !settings.onlyWhileTimerRuns || context.timerRunning
    }

    /// Titles are trimmed and cut; an empty title is no title.
    static func cleanTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
    }
}

/// The stored intervals. Value type so the rules (merge, retention, per-app removal) are testable without files.
public struct ActivityLog: Codable, Sendable, Hashable {
    public private(set) var intervals: [ActivityInterval]

    /// Two intervals of the same app (and title) that touch within this gap are one (checkpoints, short interruptions).
    public static let mergeGap: TimeInterval = 5

    public init(intervals: [ActivityInterval] = []) { self.intervals = intervals.sorted { $0.start < $1.start } }

    public var isEmpty: Bool { intervals.isEmpty }

    public mutating func append(_ interval: ActivityInterval) {
        if let last = intervals.last, last.bundleID == interval.bundleID, last.windowTitle == interval.windowTitle,
           interval.start >= last.start, interval.start.timeIntervalSince(last.end) <= Self.mergeGap {
            intervals[intervals.count - 1].end = max(last.end, interval.end)
            return
        }
        intervals.append(interval)
        intervals.sort { $0.start < $1.start }
    }

    /// Deletes everything that ended before the retention window. Returns how many were removed.
    @discardableResult
    public mutating func prune(retentionDays: Int, now: Date) -> Int {
        let cutoff = now.addingTimeInterval(-TimeInterval(max(1, retentionDays)) * 86_400)
        let before = intervals.count
        intervals.removeAll { $0.end < cutoff }
        return before - intervals.count
    }

    public mutating func removeAll() { intervals.removeAll() }

    /// Forgets everything recorded for one app (used when an app is added to the exclude list).
    @discardableResult
    public mutating func remove(bundleID: String) -> Int {
        let before = intervals.count
        intervals.removeAll { $0.bundleID == bundleID }
        return before - intervals.count
    }

    /// Removes the window titles (switching titles off removes what was stored before).
    public mutating func stripTitles() {
        for index in intervals.indices { intervals[index].windowTitle = nil }
        let merged = intervals
        intervals = []
        for interval in merged { append(interval) }
    }

    /// The intervals that overlap `[from, to)`, clipped to it.
    public func intervals(from: Date, to: Date) -> [ActivityInterval] {
        intervals.compactMap { interval in
            guard interval.end > from, interval.start < to else { return nil }
            var clipped = interval
            clipped.start = max(interval.start, from)
            clipped.end = min(interval.end, to)
            return clipped
        }
    }
}

/// Time per app in a list of intervals, longest first.
public struct ActivityAppTotal: Sendable, Hashable, Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    public let appName: String
    public let seconds: TimeInterval
}

public enum ActivitySummary {
    public static func totals(_ intervals: [ActivityInterval]) -> [ActivityAppTotal] {
        var seconds: [String: TimeInterval] = [:]
        var names: [String: String] = [:]
        for interval in intervals {
            seconds[interval.bundleID, default: 0] += interval.duration
            names[interval.bundleID] = interval.appName
        }
        return seconds.map { ActivityAppTotal(bundleID: $0.key, appName: names[$0.key] ?? $0.key, seconds: $0.value) }
            .sorted { ($0.seconds, $1.appName) > ($1.seconds, $0.appName) }
    }
}
