import Foundation

/// Re-runs `operation` after transport failures only. Callers pass the SAME `clientEventId` on every attempt, so the
/// server (idempotent over `clientEventId`) returns the first result for a replayed start/stop.
public func retryOnNetworkError<T: Sendable>(attempts: Int = 3, delay: Duration = .milliseconds(400), _ operation: @Sendable () async throws -> T) async throws -> T {
    var attempt = 0
    while true {
        do {
            return try await operation()
        } catch let error as TimetrackError where error.isNetworkError && attempt < attempts - 1 {
            attempt += 1
            try await Task.sleep(for: delay * attempt)
        }
    }
}
