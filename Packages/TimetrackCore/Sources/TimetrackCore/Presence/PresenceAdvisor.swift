import Foundation

// M2: presence signals of the Mac (screen lock, sleep, long inactivity) turned into suggestions.
//
// The Mac never stops or starts a timer on its own because of these signals: a lock can be a coffee break. The advisor only
// answers "should the user be asked?"; the app shows the question as a notification with the proposed end time, and the user decides.

public struct PresenceSettings: Codable, Sendable, Hashable {
    /// Master switch for all presence suggestions (off by default, like every automation).
    public var enabled: Bool
    /// After lock or sleep: offer to end the running timer at the moment the Mac was left, if the absence lasted long enough.
    public var askAfterAbsence: Bool
    public var minAwayMinutes: Int
    /// While unlocked but without input for a long time: offer to end the running timer at the last input.
    public var askWhenIdle: Bool
    public var idleMinutes: Int
    /// After unlock or wake at a work place with no timer running: offer to start one.
    public var suggestStartAtUnlock: Bool

    public static let awayOptions = [5, 10, 15, 30, 60]
    public static let idleOptions = [5, 10, 15, 30, 60]
    /// A start is only offered after a real absence, not after a quick lock.
    public static let minAwayForStartSeconds: TimeInterval = 5 * 60
    /// At most one start suggestion per hour.
    public static let startCooldownSeconds: TimeInterval = 60 * 60

    public init(enabled: Bool = false, askAfterAbsence: Bool = true, minAwayMinutes: Int = 10, askWhenIdle: Bool = true, idleMinutes: Int = 15,
                suggestStartAtUnlock: Bool = true) {
        self.enabled = enabled
        self.askAfterAbsence = askAfterAbsence
        self.minAwayMinutes = minAwayMinutes
        self.askWhenIdle = askWhenIdle
        self.idleMinutes = idleMinutes
        self.suggestStartAtUnlock = suggestStartAtUnlock
    }

    private enum CodingKeys: String, CodingKey { case enabled, askAfterAbsence, minAwayMinutes, askWhenIdle, idleMinutes, suggestStartAtUnlock }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        askAfterAbsence = try c.decodeIfPresent(Bool.self, forKey: .askAfterAbsence) ?? true
        minAwayMinutes = try c.decodeIfPresent(Int.self, forKey: .minAwayMinutes) ?? 10
        askWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .askWhenIdle) ?? true
        idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? 15
        suggestStartAtUnlock = try c.decodeIfPresent(Bool.self, forKey: .suggestStartAtUnlock) ?? true
    }
}

public enum PresenceReason: String, Sendable, Hashable {
    case locked, asleep, idle
}

/// The timer as the advisor needs it.
public enum PresenceTimer: Sendable, Equatable {
    case running(startedAt: Date)
    case idle
}

public enum PresenceAdvice: Sendable, Equatable {
    case none
    /// Offer "Timer beenden um `endAt`?" (the moment the user left, never the moment of the question).
    case suggestStop(endAt: Date, away: TimeInterval, reason: PresenceReason)
    /// Offer "Timer starten?" (the Mac was unlocked at a work place).
    case suggestStart(away: TimeInterval)
}

public struct PresenceAdvisor: Sendable {
    public var settings: PresenceSettings
    public private(set) var awaySince: Date?
    public private(set) var awayReason: PresenceReason = .locked
    public private(set) var lastStartSuggestion: Date?
    /// End time of the idle period a question was already asked for.
    public private(set) var idleAskedEnd: Date?

    public init(settings: PresenceSettings = PresenceSettings()) { self.settings = settings }

    /// The Mac was locked or went to sleep. The earliest moment wins (lock, then sleep: the absence started at the lock).
    public mutating func away(_ reason: PresenceReason, at date: Date) {
        if awaySince == nil { awaySince = date; awayReason = reason }
    }

    public var isAway: Bool { awaySince != nil }

    /// The Mac was unlocked or woke up.
    public mutating func returned(at now: Date, timer: PresenceTimer, atWorkPlace: Bool) -> PresenceAdvice {
        defer { awaySince = nil }
        guard settings.enabled, let since = awaySince, now > since else { return .none }
        let away = now.timeIntervalSince(since)
        switch timer {
        case .running(let startedAt):
            guard settings.askAfterAbsence, away >= TimeInterval(settings.minAwayMinutes) * 60, since > startedAt else { return .none }
            return .suggestStop(endAt: since, away: away, reason: awayReason)
        case .idle:
            guard settings.suggestStartAtUnlock, atWorkPlace, away >= PresenceSettings.minAwayForStartSeconds else { return .none }
            if let last = lastStartSuggestion, now.timeIntervalSince(last) < PresenceSettings.startCooldownSeconds { return .none }
            lastStartSuggestion = now
            return .suggestStart(away: away)
        }
    }

    /// Polled while the Mac is awake and unlocked: `idleSeconds` is the time since the last keyboard or mouse input.
    public mutating func idle(seconds idleSeconds: TimeInterval, at now: Date, timer: PresenceTimer) -> PresenceAdvice {
        guard settings.enabled, settings.askWhenIdle else { return .none }
        guard idleSeconds >= TimeInterval(settings.idleMinutes) * 60 else {
            idleAskedEnd = nil // input again: the next idle period may be asked about
            return .none
        }
        guard case .running(let startedAt) = timer, !isAway else { return .none }
        let end = now.addingTimeInterval(-idleSeconds)
        guard end > startedAt else { return .none }
        if let asked = idleAskedEnd, abs(asked.timeIntervalSince(end)) < 120 { return .none }
        idleAskedEnd = end
        return .suggestStop(endAt: end, away: idleSeconds, reason: .idle)
    }
}
