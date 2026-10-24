import Foundation

// SG1: the "Storniert" bin (contract 0.28.0, backend handoff W3). Cancelling an entry is a soft delete; these types carry the list,
// the restore and the permanent deletion (single, bulk, dry-run preview).

/// A cancelled entry with when and why it was cancelled (`GET /time/segments/cancelled`).
public struct CancelledSegment: Codable, Sendable, Hashable, Identifiable {
    public let segment: Segment
    public let cancelledAt: Date
    public let cancelReason: String?

    public var id: UUID { segment.id }

    public init(segment: Segment, cancelledAt: Date, cancelReason: String? = nil) {
        self.segment = segment
        self.cancelledAt = cancelledAt
        self.cancelReason = cancelReason
    }
}

public struct CancelledSegmentPage: Codable, Sendable, Hashable {
    public let items: [CancelledSegment]
    public let total: Int
    public let limit: Int
    public let offset: Int

    public init(items: [CancelledSegment], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }
}

/// What a permanent deletion removed (or, with `dryRun`, would remove). The only trace of a purge: the backend keeps no tombstone.
public struct PurgeSummary: Codable, Sendable, Hashable {
    public let dryRun: Bool
    public let segments: Int
    public let revisions: Int
    public let suggestions: Int
    public let timerEvents: Int
    public let automationEvents: Int

    public init(dryRun: Bool, segments: Int, revisions: Int = 0, suggestions: Int = 0, timerEvents: Int = 0, automationEvents: Int = 0) {
        self.dryRun = dryRun
        self.segments = segments
        self.revisions = revisions
        self.suggestions = suggestions
        self.timerEvents = timerEvents
        self.automationEvents = automationEvents
    }
}

/// Which cancelled entries a bulk deletion addresses. Mirrors the query of `DELETE /time/segments/cancelled`
/// (the backend refuses an empty selection with 400 `purge_scope_required`).
public enum PurgeScope: Sendable, Hashable {
    case ids([UUID])
    case all
    /// By start of the entry, `[from, to)`.
    case range(from: Date?, to: Date?)
}
