import Foundation

/// Result of a user-initiated store action. Stores report it once per action (never for loads or other passive updates),
/// so the app layer can map it to feedback such as a haptic without the stores knowing about UI frameworks.
public enum StoreOutcome: Sendable, Equatable {
    case timerStarted
    case timerStopped
    /// A create/update was accepted by the server.
    case saved
    /// A delete, void or cancel was confirmed by the server.
    case deleted
    /// The request failed (reported once per failed action, not per retry; cancellations are not failures).
    case failed
}

/// Receives `StoreOutcome`s on the main actor.
public typealias StoreOutcomeHandler = @MainActor (StoreOutcome) -> Void
