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
