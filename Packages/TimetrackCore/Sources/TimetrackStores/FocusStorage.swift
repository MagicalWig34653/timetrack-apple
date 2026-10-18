import Foundation
import TimetrackCore

/// Remembers which timer the Focus filter started, so a later "Focus off" only stops its own timer.
public struct FocusStartedTimer: Codable, Sendable, Hashable {
    public var segmentId: UUID
    public var startedAt: Date
    public init(segmentId: UUID, startedAt: Date) {
        self.segmentId = segmentId
        self.startedAt = startedAt
    }
}

/// Non-secret filter state in the App Group: mode, kind, place and bookkeeping. Never contains the session.
public struct FocusState: Codable, Sendable, Hashable {
    public var active: FocusConfiguration?
    public var activatedAt: Date?
    /// Stable id of the current activation; becomes the clientEventId of the start so a repeated callback cannot start twice.
    public var activationId: UUID?
    public var startedTimer: FocusStartedTimer?
    /// Last known state of the "automation" module (nil = unknown, treated as on).
    public var automationEnabled: Bool?
    public var settings: FocusSettings
    /// F3: monotonic stamp (milliseconds) of the last applied transition. Every callback gets `max(now, previous + 1)`, so
    /// transitions are totally ordered even when the clock steps back; notification answers carry the stamp of their question.
    public var sequence: Int64?
    /// F3: stable id of the last deactivation; becomes the clientEventId of the stop (a repeated answer cannot stop twice).
    public var deactivationId: UUID?
    /// F3: event id of a Focus start that is waiting in the retry queue (the timer it creates belongs to the Focus).
    public var queuedStartEventId: UUID?
    /// F3: what the system delivered last, for the diagnostics section.
    public var lastDelivery: FocusDeliverySummary?
    /// F3: keys ("start-<sequence>") of notification answers that were already executed (duplicate taps).
    public var handledActions: [String]?
    /// Places the filter can offer (cached by the app so the system's filter editor does not wait for the network).
    public var places: [FocusPlace]

    public init(active: FocusConfiguration? = nil, activatedAt: Date? = nil, activationId: UUID? = nil, startedTimer: FocusStartedTimer? = nil,
                automationEnabled: Bool? = nil, settings: FocusSettings = FocusSettings(), places: [FocusPlace] = []) {
        self.active = active
        self.activatedAt = activatedAt
        self.activationId = activationId
        self.startedTimer = startedTimer
        self.automationEnabled = automationEnabled
        self.settings = settings
        self.places = places
    }
}

public struct FocusPlace: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// UserDefaults-backed storage (App Group suite in the apps, a private suite in tests). Synchronous and cheap on purpose.
public struct FocusStateStore: Sendable {
    public static let key = "focus.state.v1"
    private let suiteName: String?
    private var defaults: UserDefaults? { suiteName.flatMap { UserDefaults(suiteName: $0) } }

    public init(suiteName: String? = WidgetSnapshot.appGroup) { self.suiteName = suiteName }

    public func load() -> FocusState {
        guard let data = defaults?.data(forKey: Self.key), let state = try? JSONDecoder().decode(FocusState.self, from: data) else { return FocusState() }
        return state
    }

    public func save(_ state: FocusState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    public func update(_ change: (inout FocusState) -> Void) {
        var state = load()
        change(&state)
        save(state)
    }
}

public enum FocusTrigger: String, Codable, Sendable, Hashable {
    case focusOn, focusOff, test, notificationAction
    /// F3: queued actions delivered later (app start, foreground, background refresh, "Jetzt senden").
    case retry
    /// F3: the debug hook that feeds the real delivery pipeline.
    case simulated
}

public enum FocusLogResult: Codable, Sendable, Hashable {
    case done, skipped(FocusSkipReason), notified, notificationsDenied, askedSignIn, wouldDo, failed(String)
    /// F3: the server was not reachable; the action waits in the persistent queue and is retried.
    case queued
}

public struct FocusLogEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var date: Date
    public var trigger: FocusTrigger
    public var mode: FocusMode
    public var kind: SegmentKind
    /// Short German description of what happened ("Timer gestartet", "Nachfrage gesendet", ...).
    public var summary: String
    public var result: FocusLogResult
    /// F3: what the system handed over ("Modus Nachfragen, Art Arbeit" or "keine Angaben (Fokus beendet)"). Absent in old entries.
    public var received: String?
    /// F3: technical detail (error text), shown in the diagnostics.
    public var detail: String?
    /// F3: stamp of the transition this entry belongs to.
    public var sequence: Int64?

    public init(id: UUID = UUID(), date: Date = .now, trigger: FocusTrigger, mode: FocusMode, kind: SegmentKind, summary: String, result: FocusLogResult,
                received: String? = nil, detail: String? = nil, sequence: Int64? = nil) {
        self.received = received
        self.detail = detail
        self.sequence = sequence
        self.id = id
        self.date = date
        self.trigger = trigger
        self.mode = mode
        self.kind = kind
        self.summary = summary
        self.result = result
    }
}

/// Ring buffer of the last filter actions (newest first), persisted in the App Group.
public struct FocusActionLog: Sendable {
    public static let key = "focus.log.v1"
    public static let capacity = 40
    private let suiteName: String?
    private var defaults: UserDefaults? { suiteName.flatMap { UserDefaults(suiteName: $0) } }

    public init(suiteName: String? = WidgetSnapshot.appGroup) { self.suiteName = suiteName }

    public func entries() -> [FocusLogEntry] {
        guard let data = defaults?.data(forKey: Self.key), let list = try? JSONDecoder().decode([FocusLogEntry].self, from: data) else { return [] }
        return list
    }

    public func append(_ entry: FocusLogEntry) {
        var list = entries()
        list.insert(entry, at: 0)
        if list.count > Self.capacity { list.removeLast(list.count - Self.capacity) }
        if let data = try? JSONEncoder().encode(list) { defaults?.set(data, forKey: Self.key) }
    }

    public func clear() { defaults?.removeObject(forKey: Self.key) }
}
