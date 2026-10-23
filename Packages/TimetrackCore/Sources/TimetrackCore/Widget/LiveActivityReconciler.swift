import Foundation

/// What a timer Live Activity shows. `startedAt` drives the ticking text, so it is the identity of "the same timer".
///
/// LA1: the target is also the activity's content state, so it carries everything the views need to draw without a network
/// round trip: the pause state (`pausedAt`), the finished work of today, the planned day and the account accent.
/// A pause is a normal pause: the work segment is stopped, so a paused target has no running segment; its `startedAt` is the
/// moment the pause began (the identity of "this pause").
public struct LiveActivityTarget: Sendable, Codable, Equatable, Hashable {
    public var kind: SegmentKind
    public var startedAt: Date
    /// Set while paused (equal to `startedAt`); nil while the timer runs.
    public var pausedAt: Date?
    /// Finished work of today without the running segment (what the Heute screen counts as done).
    public var workedSeconds: Int
    /// Planned length of the day (plan day's `plannedSeconds`, else the work model's target); nil when there is none.
    public var plannedSeconds: Int?
    /// Planned end of the day from the plan, when planned times exist.
    public var plannedEnd: Date?
    /// First start of today (LA2); the bar runs from here to `plannedEnd`. Nil when unknown (older snapshot).
    public var dayStart: Date?
    /// Account accent (`#RRGGBB`); nil = default blue.
    public var accentHex: String?
    /// LA4: animated work icon chosen in the settings; nil (older states) = off.
    public var iconStyle: LiveActivityIconStyle?
    /// Q1: card tint chosen in the settings; nil (older states) = subtle default. Only non-default values are stored.
    public var tintStyle: LiveActivityTintStyle?

    public init(kind: SegmentKind, startedAt: Date, pausedAt: Date? = nil, workedSeconds: Int = 0, plannedSeconds: Int? = nil,
                plannedEnd: Date? = nil, dayStart: Date? = nil, accentHex: String? = nil, iconStyle: LiveActivityIconStyle? = nil, tintStyle: LiveActivityTintStyle? = nil) {
        self.tintStyle = tintStyle
        self.kind = kind
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.workedSeconds = workedSeconds
        self.plannedSeconds = plannedSeconds
        self.plannedEnd = plannedEnd
        self.dayStart = dayStart
        self.accentHex = accentHex
        self.iconStyle = iconStyle
    }

    public var isPaused: Bool { pausedAt != nil }

    /// Server timestamps and the JSON round trip through the App Group may differ by sub-second noise. A running timer and a
    /// pause are never "the same timer".
    func sameTimer(as other: LiveActivityTarget) -> Bool {
        isPaused == other.isPaused && abs(startedAt.timeIntervalSince(other.startedAt)) < 1
    }
}

/// One activity that is currently alive (active or stale; ended/dismissed ones are filtered out by the caller).
public struct LiveActivityExisting: Sendable, Equatable {
    public var id: String
    public var target: LiveActivityTarget

    public init(id: String, target: LiveActivityTarget) {
        self.id = id
        self.target = target
    }
}

/// What to do so that the set of activities mirrors the timer. Pure data; `TimerLiveActivity` executes it.
public struct LiveActivityPlan: Sendable, Equatable {
    /// Activity to keep, with new content when it differs (updating works in the background, requesting does not).
    public var keep: String?
    public var update: LiveActivityTarget?
    public var end: [String]
    /// Needs `Activity.request`, which iOS only allows while the app is in the foreground.
    public var start: LiveActivityTarget?

    public var isNoOp: Bool { update == nil && end.isEmpty && start == nil }
}

/// Timer running => exactly one activity with the timer's start date; no timer => none. Idempotent: applying the plan and
/// planning again yields a no-op, so it may run at every app activation, after queue retries and after every refresh.
public enum LiveActivityReconciler {
    public static func plan(desired: LiveActivityTarget?, existing: [LiveActivityExisting]) -> LiveActivityPlan {
        guard let desired else { return LiveActivityPlan(keep: nil, update: nil, end: existing.map(\.id), start: nil) }
        // Prefer an exact match, then the same timer with another kind, then any activity (re-pointed with `update`, which
        // also works in the background, instead of ending it and failing to request a new one there).
        let keeper = existing.first { $0.target == desired }
            ?? existing.first { $0.target.sameTimer(as: desired) }
            ?? existing.first
        guard let keeper else { return LiveActivityPlan(keep: nil, update: nil, end: [], start: desired) }
        return LiveActivityPlan(keep: keeper.id, update: keeper.target == desired ? nil : desired,
                                end: existing.filter { $0.id != keeper.id }.map(\.id), start: nil)
    }
}

/// Runs bodies one after another (an async mutex). Used so concurrent reconciles (app model sync, Focus callback, foreground)
/// cannot both see "no activity" and request two.
public actor SerialGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func run<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
        if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true }
        let value = await body()
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        return value
    }
}

/// Result of the last reconcile, kept in the App Group so the Focus page can show why an activity is missing.
public struct LiveActivityOutcome: Codable, Sendable, Equatable {
    public enum Result: String, Codable, Sendable { case none, kept, updated, started, ended, startDeferred, startFailed, disabled }
    public var date: Date
    public var result: Result
    /// Where the reconcile ran (`focus`, `foreground`, `model`, ...).
    public var source: String
    public var detail: String?

    public init(date: Date = .now, result: Result, source: String, detail: String? = nil) {
        self.date = date
        self.result = result
        self.source = source
        self.detail = detail
    }
}

extension LiveActivityOutcome {
    /// One line for the Focus page and the shared diagnostics (no secrets: only the result, the source and the system's error text).
    public var germanSummary: String {
        let text: String
        switch result {
        case .none: text = "keine Live Activity nötig (kein Timer)"
        case .kept: text = "Live Activity läuft bereits"
        case .updated: text = "Live Activity aktualisiert"
        case .started: text = "Live Activity gestartet"
        case .ended: text = "Live Activity beendet"
        case .startDeferred: text = "Start im Hintergrund nicht möglich; wird beim Öffnen der App nachgeholt"
        case .startFailed: text = "Start fehlgeschlagen"
        case .disabled: text = "Live Activities sind ausgeschaltet"
        }
        return "\(text) (\(source)\(detail.map { ", \($0)" } ?? ""))"
    }
}

public struct LiveActivityOutcomeStore: Sendable {
    private let suiteName: String?
    private static let key = "liveactivity.lastOutcome.v1"

    public init(suiteName: String? = WidgetSnapshot.appGroup) { self.suiteName = suiteName }

    private var defaults: UserDefaults? { suiteName.flatMap { UserDefaults(suiteName: $0) } }

    public func read() -> LiveActivityOutcome? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(LiveActivityOutcome.self, from: data)
    }

    public func write(_ outcome: LiveActivityOutcome) {
        guard let data = try? JSONEncoder().encode(outcome) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}
