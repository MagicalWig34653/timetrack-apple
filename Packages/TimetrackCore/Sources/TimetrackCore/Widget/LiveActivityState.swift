import Foundation

// LA1: pure state, progress and planned-end logic of the timer Live Activity. No ActivityKit here, so it is unit tested.

/// A pause the user started from the Live Activity (or the lock screen). The server only knows "no timer running"; this marker
/// remembers that the stop was a pause, so the activity can offer "Weiter" with the same kind instead of vanishing.
public struct PauseMarker: Codable, Sendable, Equatable {
    public var kind: SegmentKind
    public var pausedAt: Date

    public init(kind: SegmentKind, pausedAt: Date) {
        self.kind = kind
        self.pausedAt = pausedAt
    }

    /// A pause older than this is treated as the end of work (iOS also ends activities after 8 hours).
    public static let maxAge: TimeInterval = 4 * 3600

    public func isActive(at now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(pausedAt)
        return age >= -60 && age <= Self.maxAge
    }

    /// The marker that still counts: none while a timer runs (resumed elsewhere, e.g. in the web app) and none once it expired.
    /// A stop that did not come from a pause never creates a marker, so it ends the activity as before.
    public static func current(_ stored: PauseMarker?, running: Bool, at now: Date = .now) -> PauseMarker? {
        guard let stored, !running, stored.isActive(at: now) else { return nil }
        return stored
    }
}

/// Storage of the pause marker in the App Group (the app, its intents and the extension read the same value).
public struct PauseMarkerStore: Sendable {
    private let suiteName: String?
    private static let key = "liveactivity.pause.v1"

    public init(suiteName: String? = WidgetSnapshot.appGroup) { self.suiteName = suiteName }

    private var defaults: UserDefaults? { suiteName.flatMap { UserDefaults(suiteName: $0) } }

    public func read() -> PauseMarker? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(PauseMarker.self, from: data)
    }

    public func write(_ marker: PauseMarker) {
        guard let data = try? JSONEncoder().encode(marker) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    public func clear() { defaults?.removeObject(forKey: Self.key) }
}

extension LiveActivityTarget {
    /// What the activity should show for the current snapshot: running timer, a paused timer (marker) or nothing.
    /// Totals and the plan only count on the day they were written for.
    public static func desired(snapshot: WidgetSnapshot?, pause: PauseMarker?, iconStyle: LiveActivityIconStyle = .off, tintStyle: LiveActivityTintStyle = .default, now: Date = .now) -> LiveActivityTarget? {
        let running = snapshot?.isRunning == true && snapshot?.startedAt != nil
        let sameDay = snapshot?.todaySeconds(at: now) != nil
        let worked = sameDay ? (snapshot?.todaySeconds ?? 0) : 0
        // UX3: a trip is not part of the workday: no day bar, no planned end, no estimate while the kind is "Fahrt".
        let kindShown = running ? snapshot?.kind : PauseMarker.current(pause, running: running, at: now)?.kind
        let workday = sameDay && kindShown != .travel
        let planned = workday ? snapshot.flatMap { $0.plannedSeconds ?? ($0.targetSeconds.flatMap { $0 > 0 ? $0 : nil }) } : nil
        let plannedEnd = workday ? snapshot?.plannedEnd : nil
        let dayStart = workday ? snapshot?.firstStart : nil
        let accent = snapshot?.accentHex
        let icon: LiveActivityIconStyle? = iconStyle.isAnimated ? iconStyle : nil
        let tint: LiveActivityTintStyle? = tintStyle == .default ? nil : tintStyle
        if running, let snapshot, let startedAt = snapshot.startedAt {
            return LiveActivityTarget(kind: snapshot.kind, startedAt: startedAt, workedSeconds: worked, plannedSeconds: planned,
                                      plannedEnd: plannedEnd, dayStart: dayStart, accentHex: accent, iconStyle: icon, tintStyle: tint)
        }
        if let marker = PauseMarker.current(pause, running: running, at: now) {
            return LiveActivityTarget(kind: marker.kind, startedAt: marker.pausedAt, pausedAt: marker.pausedAt, workedSeconds: worked,
                                      plannedSeconds: planned, plannedEnd: plannedEnd, dayStart: dayStart, accentHex: accent, iconStyle: icon, tintStyle: tint)
        }
        return nil
    }
}

/// What the activity says about the end of the day.
public enum LiveActivityEnd: Sendable, Equatable {
    /// From the plan day's planned times (a plan, not a booking).
    case planned(Date)
    /// No plan times: when the daily target is reached if the timer keeps running (running only; a pause has no estimate).
    case estimated(Date)
    /// Target already reached.
    case reached
}

extension LiveActivityTarget {
    /// Work of today at `date`: finished work plus the running segment; constant while paused.
    public func workedSeconds(at date: Date) -> Int {
        guard !isPaused else { return finishedSeconds }
        return finishedSeconds + Self.wholeSeconds(date.timeIntervalSince(startedAt))
    }

    /// Day bar from the first start of today to the planned end (LA2). Nil without a planned end, without a plausible order or
    /// when the first start is unknown and the worked origin would be needed (then the bar falls back to worked time).
    public var dayInterval: ClosedRange<Date>? {
        guard let plannedEnd else { return nil }
        let start = dayStart ?? workedOrigin
        return start < plannedEnd ? start...plannedEnd : nil
    }

    /// Progress of the day, 0...1. With a planned end: how far the time between the first start and Feierabend has passed (it keeps
    /// moving during a pause, because Feierabend comes closer). Without one: worked time against the planned length.
    public func fraction(at date: Date) -> Double? {
        if let day = dayInterval {
            let total = day.upperBound.timeIntervalSince(day.lowerBound)
            return min(1, max(0, date.timeIntervalSince(day.lowerBound) / total))
        }
        guard let plannedSeconds, plannedSeconds > 0 else { return nil }
        return min(1, max(0, Double(workedSeconds(at: date)) / Double(plannedSeconds)))
    }

    /// Instant from which "today's work" counts upwards while running (`startedAt` minus the finished work). `Text(timerInterval:)`
    /// drives the clock from it, so it ticks without any update of the activity.
    public var workedOrigin: Date { startedAt.addingTimeInterval(-TimeInterval(finishedSeconds)) }

    /// `workedSeconds` as the views may rely on it: never negative. A negative value (stale or foreign content state) would turn a
    /// `Text(timerInterval:)` range upside down, and SwiftUI traps on a range whose end precedes its start (LA2).
    var finishedSeconds: Int { min(max(0, workedSeconds), 1_000_000_000) }

    /// Non-negative whole seconds; never traps on NaN or infinity (`Int(Double)` does).
    static func wholeSeconds(_ interval: TimeInterval) -> Int {
        guard interval.isFinite else { return 0 }
        return Int(min(max(interval, 0), 4_000_000_000))
    }

    /// The range and pause time for `Text(timerInterval:pauseTime:)` of today's work clock; the range is always valid
    /// (start before end), whatever the state holds.
    public var clock: (range: ClosedRange<Date>, pauseTime: Date?) {
        let origin = workedOrigin
        guard isPaused else { return (origin...Date.distantFuture, nil) }
        let frozen = origin.addingTimeInterval(TimeInterval(finishedSeconds))
        return (origin...frozen.addingTimeInterval(1), frozen)
    }

    /// Range for `ProgressView(timerInterval:)`: the day bar, else (running only) worked time against the planned length.
    public var progressInterval: ClosedRange<Date>? {
        if let day = dayInterval { return day }
        guard !isPaused, let plannedSeconds, plannedSeconds > 0 else { return nil }
        return workedOrigin...workedOrigin.addingTimeInterval(TimeInterval(plannedSeconds))
    }

    /// True when the bar's left label can name a real first start.
    public var hasDayStart: Bool { dayStart != nil && dayInterval != nil }

    /// The planned end if the plan has one, else the estimate for reaching the target while the timer runs.
    public func end(at date: Date) -> LiveActivityEnd? {
        if let plannedEnd { return .planned(plannedEnd) }
        guard let plannedSeconds, plannedSeconds > 0 else { return nil }
        if workedSeconds(at: date) >= plannedSeconds { return .reached }
        guard !isPaused else { return nil }
        return .estimated(startedAt.addingTimeInterval(TimeInterval(max(0, plannedSeconds - workedSeconds))))
    }
}
