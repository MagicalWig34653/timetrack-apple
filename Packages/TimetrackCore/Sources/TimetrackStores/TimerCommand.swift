import Foundation
import TimetrackCore

/// One-shot start/stop used by App Intents and Home-screen quick actions, which run without the app's stores.
/// Both calls are idempotent from the user's view: starting a running timer or stopping an idle one is reported, not an error.
public enum TimerCommand {
    public enum Outcome: Sendable, Equatable {
        case started(Segment)
        case alreadyRunning(Segment)
        case stopped(Segment)
        case notRunning
        /// H5: the last finished entry of today was continued (reopened, or a new entry from now when the server cannot reopen).
        case continued(Segment, TimerActionQueue.ResumeMode)
        /// H5: nothing to continue (no finished entry of today, or something is running already).
        case nothingToContinue
    }

    /// H4/H5: the most recent finished, startable entry of a day (not voided, kind work/travel/school). Shared by the stores and the one-shot intents.
    public static func continuable(in segments: [Segment]) -> Segment? {
        segments.filter { !$0.voided && $0.endedAt != nil && SegmentKind.selectable.contains($0.kind) }
            .max { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
    }

    /// H5: "Letzten Timer fortführen" without the app's stores (Shortcuts, Siri): reads the timer and today's entries, then reopens the last
    /// finished one (fallback: new entry of the same kind from now). `startNew` skips the reopen ("Neu starten", the gap stays a pause).
    public static func continueLast(client: APIClient, today: LocalDay, startNew: Bool = false, eventId: UUID = UUID()) async throws -> Outcome {
        if let running = try await client.currentTimer() { return .alreadyRunning(running) }
        let day = try await client.getDay(today)
        guard let segment = continuable(in: day.segments ?? []) else { return .nothingToContinue }
        let target = QueuedTimerAction.ContinueTarget(segment)
        let result = try await retryOnNetworkError { try await TimerActionQueue.resume(target, client: client, clientEventId: eventId, startNewOnly: startNew) }
        return .continued(result.segment, result.mode)
    }

    public static func start(client: APIClient, kind: SegmentKind = .work, placeId: UUID? = nil, eventId: UUID = UUID()) async throws -> Outcome {
        if let running = try await client.currentTimer() { return .alreadyRunning(running) }
        let segment = try await retryOnNetworkError { try await client.startTimer(clientEventId: eventId, kind: kind, placeId: placeId) }
        return .started(segment)
    }

    public static func stop(client: APIClient, eventId: UUID = UUID()) async throws -> Outcome {
        guard try await client.currentTimer() != nil else { return .notRunning }
        let segment = try await retryOnNetworkError { try await client.stopTimer(clientEventId: eventId) }
        return .stopped(segment)
    }
}
