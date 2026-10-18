import Foundation
import TimetrackCore

/// What Timetrack does when the system Focus that carries the filter turns on or off.
public enum FocusMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// Do nothing (the filter only records that a Focus is active).
    case off
    /// Ask with a notification before starting/stopping the timer.
    case suggest
    /// Start/stop the timer without asking.
    case direct
}

/// The non-secret configuration of one Focus filter (what the user picked in the system Focus settings).
public struct FocusConfiguration: Codable, Sendable, Hashable {
    public var mode: FocusMode
    public var kind: SegmentKind
    public var placeId: UUID?
    public var placeName: String?
    /// Optional free text the user gave the filter so messages can say "Fokus ‚Arbeit'" (the system never reveals the Focus name).
    public var focusName: String?

    public init(mode: FocusMode, kind: SegmentKind = .work, placeId: UUID? = nil, placeName: String? = nil, focusName: String? = nil) {
        self.mode = mode
        self.kind = SegmentKind.selectable.contains(kind) ? kind : .work
        self.placeId = placeId
        self.placeName = placeName
        self.focusName = focusName.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

public enum FocusEvent: Sendable, Hashable {
    case activated(FocusConfiguration)
    case deactivated(FocusConfiguration)
}

/// How a new filter callback relates to the filter that was active before. The system calls the filter intent when a Focus
/// turns on and again (with an empty/default configuration) when it turns off, so "off" is derived from the stored state.
public enum FocusTransition {
    /// `incoming == nil` means "no usable configuration" (the Focus ended). A Focus-to-Focus switch (previous and incoming both
    /// active) is treated as a hand-over: nothing is stopped, the new configuration is activated (the start is deduplicated).
    public static func events(previous: FocusConfiguration?, incoming: FocusConfiguration?) -> [FocusEvent] {
        switch (previous, incoming) {
        case (nil, nil): return []
        case (let old?, nil): return [.deactivated(old)]
        case (nil, let new?): return [.activated(new)]
        case (let old?, let new?):
            if new.mode == .off { return [.deactivated(old)] } // switched to a Focus that must do nothing: the old one ended
            return [.activated(new)]
        }
    }
}

/// The timer situation a decision is made on. `startedByFocus` is true only for a timer the Focus filter itself started.
public struct FocusTimerState: Sendable, Hashable {
    public var running: Bool
    public var kind: SegmentKind?
    public var startedByFocus: Bool
    public init(running: Bool, kind: SegmentKind? = nil, startedByFocus: Bool = false) {
        self.running = running
        self.kind = kind
        self.startedByFocus = startedByFocus
    }
    public static let idle = FocusTimerState(running: false)
}

public struct FocusSettings: Codable, Sendable, Hashable {
    /// "Auch manuell gestartete Timer beenden", default off.
    public var stopManuallyStarted: Bool
    public init(stopManuallyStarted: Bool = false) { self.stopManuallyStarted = stopManuallyStarted }
}

public enum FocusSkipReason: String, Codable, Sendable, Hashable {
    case modeOff, automationOff, alreadyRunning, otherTimerRunning, notRunning, otherKind, startedManually
    /// F3: the same activation arrived twice within a few seconds.
    case duplicate
    /// F3: "Focus ended" arrived but no active Focus was stored (already ended, or the start was never delivered).
    case notActive
    /// F3: a notification answer for an activation that has been superseded (the Focus changed since the question).
    case stale
}

/// What to do. Pure result of `FocusDecision.decide`; executing it is the runner's job.
public enum FocusDecision: Sendable, Hashable {
    case noop(FocusSkipReason)
    case notifyStart, notifyStop
    case start, stop
    case askSignIn

    /// Truth table (also covered by tests):
    /// - module/automation switched off, mode off: nothing
    /// - activation: timer running (same kind -> alreadyRunning, other kind -> otherTimerRunning): nothing; idle: ask/start
    /// - deactivation: idle: nothing; other kind: nothing; not started by the Focus and setting off: nothing; else ask/stop
    /// - an action needed but there is no usable session: askSignIn (never when nothing would have to be done)
    public static func decide(event: FocusEvent, timer: FocusTimerState, settings: FocusSettings, hasSession: Bool, automationEnabled: Bool = true) -> FocusDecision {
        let configuration: FocusConfiguration
        let activating: Bool
        switch event {
        case .activated(let value): configuration = value; activating = true
        case .deactivated(let value): configuration = value; activating = false
        }
        guard configuration.mode != .off else { return .noop(.modeOff) }
        guard automationEnabled else { return .noop(.automationOff) }

        if activating {
            if timer.running { return .noop(timer.kind == configuration.kind ? .alreadyRunning : .otherTimerRunning) }
        } else {
            guard timer.running else { return .noop(.notRunning) }
            guard timer.kind == configuration.kind else { return .noop(.otherKind) }
            guard timer.startedByFocus || settings.stopManuallyStarted else { return .noop(.startedManually) }
        }
        guard hasSession else { return .askSignIn }
        switch (configuration.mode, activating) {
        case (.suggest, true): return .notifyStart
        case (.suggest, false): return .notifyStop
        case (.direct, true): return .start
        case (.direct, false): return .stop
        case (.off, _): return .noop(.modeOff)
        }
    }
}

/// German wording for notifications, the explainer page and the action log (pure, tested).
public enum FocusText {
    public static func kindName(_ kind: SegmentKind) -> String {
        switch kind {
        case .work: "Arbeit"
        case .travel: "Fahrt"
        case .school: "Schule"
        case .unknown: "Arbeit"
        }
    }

    public static func modeName(_ mode: FocusMode) -> String {
        switch mode {
        case .off: "Nichts tun"
        case .suggest: "Nachfragen"
        case .direct: "Automatisch starten und stoppen"
        }
    }

    /// "Fokus „Arbeit“" or just "Fokus" when the filter has no name.
    public static func focusLabel(_ configuration: FocusConfiguration) -> String {
        configuration.focusName.map { "Fokus „\($0)“" } ?? "Fokus"
    }

    /// Status line: "Aktiv: Fokus „Arbeit“ → Nachfragen, Art Arbeit".
    public static func activeSummary(_ configuration: FocusConfiguration) -> String {
        var text = "Aktiv: \(focusLabel(configuration)) → \(modeName(configuration.mode)), Art \(kindName(configuration.kind))"
        if let place = configuration.placeName { text += ", Ort \(place)" }
        return text
    }

    public static func startNotification(_ configuration: FocusConfiguration) -> (title: String, body: String) {
        ("\(focusLabel(configuration)) ist an", "Timer starten? (\(kindName(configuration.kind)))")
    }

    public static func stopNotification(_ configuration: FocusConfiguration) -> (title: String, body: String) {
        ("\(focusLabel(configuration)) beendet", "Timer stoppen? (\(kindName(configuration.kind)))")
    }

    public static let signInNotification = (title: "Bitte in Timetrack anmelden", body: "Der Fokus-Filter kann den Timer erst bedienen, wenn du angemeldet bist.")

    public static func skip(_ reason: FocusSkipReason, kind: SegmentKind) -> String {
        switch reason {
        case .modeOff: "Modus „Nichts tun“: nichts passiert."
        case .automationOff: "Die Automatik ist in Timetrack ausgeschaltet."
        case .alreadyRunning: "Ein Timer (\(kindName(kind))) läuft schon."
        case .otherTimerRunning: "Es läuft schon ein Timer anderer Art; er bleibt unberührt."
        case .notRunning: "Es läuft kein Timer."
        case .otherKind: "Der laufende Timer hat eine andere Art (nicht \(kindName(kind))); er läuft weiter."
        case .startedManually: "Der Timer wurde von Hand gestartet und läuft weiter."
        case .duplicate: "Doppelte Meldung des Systems ignoriert."
        case .notActive: "Fokus-Ende gemeldet, aber es war kein Fokus gespeichert; nichts getan."
        case .stale: "Veraltete Antwort ignoriert: Der Fokus hat sich seit der Frage geändert."
        }
    }
}
