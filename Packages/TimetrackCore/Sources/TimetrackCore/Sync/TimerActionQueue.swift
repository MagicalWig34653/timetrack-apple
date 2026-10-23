import Foundation

/// A timer start/stop that could not reach the server yet. The `id` is the `clientEventId` of every send attempt, so the
/// server (idempotent over it) never records an action twice, even if an earlier attempt did arrive.
public struct QueuedTimerAction: Codable, Sendable, Equatable, Identifiable {
    public enum Command: Codable, Sendable, Equatable {
        case start(SegmentKind)
        case stop
        /// H4: continue a finished segment (reopen it); `ContinueTarget` carries what a fallback start needs.
        case resume(ContinueTarget)
    }

    /// The finished segment a "Fortführen" continues. Reopen is tried first; if the server refuses, a new segment of the same kind/place/note starts.
    public struct ContinueTarget: Codable, Sendable, Equatable {
        public let segmentId: UUID
        public let version: Int
        public let kind: SegmentKind
        public let placeId: UUID?
        public let note: String?
        public init(segmentId: UUID, version: Int, kind: SegmentKind, placeId: UUID?, note: String?) {
            self.segmentId = segmentId; self.version = version; self.kind = kind; self.placeId = placeId; self.note = note
        }
        public init(_ segment: Segment) { self.init(segmentId: segment.id, version: segment.version, kind: segment.kind, placeId: segment.placeId, note: segment.note) }
    }

    public let id: UUID
    public let command: Command
    /// When the user pressed the button; the server records the time of delivery, so a late delivery is corrected back to this.
    public let queuedAt: Date
    /// Optional place for a start (F3: the Focus filter can book a start with a place). Absent in entries written before F3.
    public let placeId: UUID?
    /// L4 (optional): reason recorded with the correction when a late delivery is moved back to `queuedAt`. Default: "Offline gestartet/gestoppt".
    public let correctionReason: String?

    public init(id: UUID = UUID(), command: Command, queuedAt: Date = .now, placeId: UUID? = nil, correctionReason: String? = nil) {
        self.id = id
        self.command = command
        self.queuedAt = queuedAt
        self.placeId = placeId
        self.correctionReason = correctionReason
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
        case (.start, .start), (.stop, .stop), (.start, .resume), (.resume, .start), (.resume, .resume): true
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
            let segment = try await client.startTimer(clientEventId: action.id, kind: kind, placeId: action.placeId)
            if late, segment.startedAt > action.queuedAt.addingTimeInterval(Self.backdateThreshold / 2) {
                _ = try? await client.correctSegment(id: segment.id, SegmentCorrection(startedAt: action.queuedAt, reason: action.correctionReason ?? "Offline gestartet"), ifMatchVersion: segment.version)
            }
        case .resume(let target):
            _ = try await Self.resume(target, client: client, clientEventId: action.id)
        case .stop:
            let segment = try await client.stopTimer(clientEventId: action.id)
            if late, let end = segment.endedAt, end > action.queuedAt.addingTimeInterval(Self.backdateThreshold / 2) {
                _ = try? await client.correctSegment(id: segment.id, SegmentCorrection(endedAt: action.queuedAt, reason: action.correctionReason ?? "Offline gestoppt"), ifMatchVersion: segment.version)
            }
        }
    }

    /// How a continue ended: the segment was reopened, or (server without/rejecting reopen) a new segment was started.
    public enum ResumeMode: Sendable, Equatable { case reopened, startedNew }

    /// Tries to reopen (`endedAt: null`); on a refusal that means "not supported / not allowed" starts a new segment of the same kind
    /// and place from now. Network errors and 5xx/429 propagate (the caller queues).
    public static func resume(_ target: QueuedTimerAction.ContinueTarget, client: APIClient, clientEventId: UUID, startNewOnly: Bool = false) async throws -> (segment: Segment, mode: ResumeMode) {
        if !startNewOnly { do {
            let segment = try await client.correctSegment(id: target.segmentId, SegmentCorrection(reason: "Timer fortgesetzt", reopen: true), ifMatchVersion: target.version)
            if segment.endedAt == nil { return (segment, .reopened) }
            // A server that ignores the unknown null silently answers a closed segment: treat as unsupported.
        } catch let error as TimetrackError {
            let status = error.status ?? 0
            if error.isNetworkError || error == .cancelled || error.isUnauthorized || status >= 500 || status == 429 { throw error }
        } }
        let started = try await client.startTimer(clientEventId: clientEventId, kind: target.kind, placeId: target.placeId)
        if let note = target.note, !note.isEmpty {
            _ = try? await client.correctSegment(id: started.id, SegmentCorrection(note: note, reason: "Notiz übernommen"), ifMatchVersion: started.version)
        }
        return (started, .startedNew)
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
