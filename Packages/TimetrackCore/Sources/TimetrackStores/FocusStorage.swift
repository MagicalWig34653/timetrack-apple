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
}

public enum FocusLogResult: Codable, Sendable, Hashable {
    case done, skipped(FocusSkipReason), notified, notificationsDenied, askedSignIn, wouldDo, failed(String)
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

    public init(id: UUID = UUID(), date: Date = .now, trigger: FocusTrigger, mode: FocusMode, kind: SegmentKind, summary: String, result: FocusLogResult) {
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
    public static let capacity = 20
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
