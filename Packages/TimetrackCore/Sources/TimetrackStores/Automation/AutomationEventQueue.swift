import Foundation
import TimetrackCore

public struct QueuedEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID { event.eventId }
    public let event: AutomationEventPayload
    public let placeName: String
    public let queuedAt: Date
    public var attempts: Int
}

public struct DrainReport: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case sent(AutomationEventResult.Kind)
        /// Rejected for good (bad request, unknown place, too old): removed from the queue.
        case dropped(code: String)
    }

    public let queued: QueuedEvent
    public let outcome: Outcome
}

public struct DrainSummary: Sendable, Equatable {
    public enum Stop: Sendable, Equatable {
        case finished
        /// Offline, server error or rate limit: the rest stays queued for the next attempt.
        case retryLater
        /// Token missing, revoked or expired: needs the user (create a new device token).
        case unauthorized
    }

    public var reports: [DrainReport] = []
    public var stop: Stop = .finished
}

/// Persistent, ordered, idempotent outbox for automation events. Every event keeps the id it was queued with, so a retry after a lost
/// answer is recognised by the server (duplicate returns the first result) and never books twice.
public actor AutomationEventQueue {
    public static let maxAge: TimeInterval = 7 * 86_400
    public static let maxCount = 200

    private let storage: BlobStorage
    private let now: @Sendable () -> Date
    private var items: [QueuedEvent]

    public init(storage: BlobStorage, now: @escaping @Sendable () -> Date = { .now }) {
        self.storage = storage
        self.now = now
        let decoder = JSONCoding.makeDecoder()
        items = storage.load().flatMap { try? decoder.decode([QueuedEvent].self, from: $0) } ?? []
    }

    public var pending: [QueuedEvent] { items }
    public var count: Int { items.count }

    /// Adds an event unless one with the same id is queued already. Returns whether it was added.
    @discardableResult
    public func enqueue(_ event: AutomationEventPayload, placeName: String) -> Bool {
        guard !items.contains(where: { $0.event.eventId == event.eventId }) else { return false }
        items.append(QueuedEvent(event: event, placeName: placeName, queuedAt: now(), attempts: 0))
        if items.count > Self.maxCount { items.removeFirst(items.count - Self.maxCount) }
        persist()
        return true
    }

    /// Sends the queue oldest first (the server orders per device and place, so order matters) and stops at the first transient failure.
    public func drain(using sender: AutomationEventSending) async -> DrainSummary {
        var summary = DrainSummary()
        while let first = items.first {
            if now().timeIntervalSince(first.queuedAt) > Self.maxAge {
                items.removeFirst()
                summary.reports.append(DrainReport(queued: first, outcome: .dropped(code: "expired")))
                persist()
                continue
            }
            do {
                let result = try await sender.send(first.event)
                items.removeFirst()
                summary.reports.append(DrainReport(queued: first, outcome: .sent(result.result)))
                persist()
            } catch let error as TimetrackError {
                items[0].attempts += 1
                persist()
                switch error {
                case .api(let status, let code, _):
                    if status == 401 { summary.stop = .unauthorized; return summary }
                    if status == 429 || status >= 500 { summary.stop = .retryLater; return summary }
                    items.removeFirst()
                    summary.reports.append(DrainReport(queued: first, outcome: .dropped(code: code)))
                    persist()
                case .cancelled:
                    summary.stop = .retryLater
                    return summary
                default:
                    summary.stop = .retryLater
                    return summary
                }
            } catch {
                summary.stop = .retryLater
                return summary
            }
        }
        return summary
    }

    public func removeAll() {
        items = []
        persist()
    }

    private func persist() {
        if let data = try? JSONCoding.makeEncoder().encode(items) { storage.save(data) }
    }
}
