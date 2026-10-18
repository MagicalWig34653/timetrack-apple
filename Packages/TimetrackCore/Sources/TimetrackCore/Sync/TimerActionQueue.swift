import Foundation

/// A timer start/stop that could not reach the server yet. The `id` is the `clientEventId` of every send attempt, so the
/// server (idempotent over it) never records an action twice, even if an earlier attempt did arrive.
public struct QueuedTimerAction: Codable, Sendable, Equatable, Identifiable {
    public enum Command: Codable, Sendable, Equatable {
        case start(SegmentKind)
        case stop
    }

    public let id: UUID
    public let command: Command
    /// When the user pressed the button; the server records the time of delivery, so a late delivery is corrected back to this.
    public let queuedAt: Date

    public init(id: UUID = UUID(), command: Command, queuedAt: Date = .now) {
        self.id = id
        self.command = command
        self.queuedAt = queuedAt
    }
}

/// Small persistent queue of timer actions (JSON file in the app's container, never in a shared location).
///
/// Rules: at most `limit` entries (the oldest is dropped first); a start directly after a queued start (or a stop after a
/// stop) is ignored because it would be rejected by the server anyway. Delivery keeps the order.
public actor TimerActionQueue {
    public struct DrainResult: Sendable, Equatable {
        public var delivered = 0
        public var dropped = 0
        public var remaining = 0
        /// Delivery stopped because the server could not be reached.
        public var offline = false
        /// Delivery stopped because the session was rejected (401).
        public var unauthorized = false
    }

    /// Deliveries later than this after the button press are corrected to the press time.
    public static let backdateThreshold: TimeInterval = 20

    private let fileURL: URL?
    private let limit: Int
    private(set) var entries: [QueuedTimerAction]
    private var draining = false

    /// `fileURL == nil` keeps the queue in memory only (tests).
    public init(fileURL: URL?, limit: Int = 8) {
        self.fileURL = fileURL
        self.limit = limit
        if let fileURL, let data = try? Data(contentsOf: fileURL), let stored = try? JSONCoding.makeDecoder().decode([QueuedTimerAction].self, from: data) {
            entries = Array(stored.suffix(limit))
        } else {
            entries = []
        }
    }

    public var pending: [QueuedTimerAction] { entries }
    public var count: Int { entries.count }

    /// Queues an action; returns false when it was redundant (same command as the newest queued one).
    @discardableResult
    public func enqueue(_ action: QueuedTimerAction) -> Bool {
        if let last = entries.last, Self.sameKind(last.command, action.command) { return false }
        entries.append(action)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        persist()
        return true
    }

    public func clear() {
        entries = []
        persist()
    }

    private static func sameKind(_ a: QueuedTimerAction.Command, _ b: QueuedTimerAction.Command) -> Bool {
        switch (a, b) {
        case (.start, .start), (.stop, .stop): true
        default: false
        }
    }

    /// Delivers the queued actions in order. Network errors stop the run and keep the rest; a 401 stops it too (the caller
    /// handles the session); other rejections drop the entry (a stuck entry must never block later ones).
    public func drain(client: APIClient, now: Date = .now) async -> DrainResult {
        var result = DrainResult()
        guard !draining else { result.remaining = entries.count; return result }
        draining = true
        defer { draining = false }
        while let action = entries.first {
            do {
                try await deliver(action, client: client, now: now)
                result.delivered += 1
            } catch let error as TimetrackError where error.isNetworkError || error == .cancelled {
                result.offline = error.isNetworkError
                break
            } catch let error as TimetrackError where error.isUnauthorized {
                result.unauthorized = true
                break
            } catch let error as TimetrackError where Self.isAlreadyApplied(error) {
                result.dropped += 1
            } catch let error as TimetrackError where (error.status ?? 0) >= 500 || error.status == 429 {
                result.offline = true
                break
            } catch {
                result.dropped += 1
            }
            entries.removeFirst()
            persist()
        }
        result.remaining = entries.count
        return result
    }

    /// 409 means the server already is in the state the action wanted (timer running / not running).
    private static func isAlreadyApplied(_ error: TimetrackError) -> Bool {
        error.code == APIErrorCode.timerAlreadyRunning.rawValue || error.code == APIErrorCode.noRunningTimer.rawValue
    }

    private func deliver(_ action: QueuedTimerAction, client: APIClient, now: Date) async throws {
        let late = now.timeIntervalSince(action.queuedAt) > Self.backdateThreshold
        switch action.command {
        case .start(let kind):
            let segment = try await client.startTimer(clientEventId: action.id, kind: kind)
            if late, segment.startedAt > action.queuedAt.addingTimeInterval(Self.backdateThreshold / 2) {
                _ = try? await client.correctSegment(id: segment.id, SegmentCorrection(startedAt: action.queuedAt, reason: "Offline gestartet"), ifMatchVersion: segment.version)
            }
        case .stop:
            let segment = try await client.stopTimer(clientEventId: action.id)
            if late, let end = segment.endedAt, end > action.queuedAt.addingTimeInterval(Self.backdateThreshold / 2) {
                _ = try? await client.correctSegment(id: segment.id, SegmentCorrection(endedAt: action.queuedAt, reason: "Offline gestoppt"), ifMatchVersion: segment.version)
            }
        }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONCoding.makeEncoder().encode(entries).write(to: fileURL, options: [.atomic])
        } catch {
            // The queue is best effort; an unwritable container only loses persistence across launches.
        }
    }
}
