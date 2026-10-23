import Foundation

// Q1: "n zu prüfen". The backend flags a segment (`needsReview`) in exactly one situation: the automation started it and the
// departure never arrived (`missingDeparture`, then an "end" suggestion is created). The flag is never cleared by the backend
// (not by a correction, not by accepting the suggestion), so the app keeps a local list of segments the user has dealt with.

/// Why an entry needs a look, in terms the UI can explain in plain German.
public enum ReviewReason: Hashable, Sendable {
    /// Still open, and the automation proposes this end.
    case endMissingProposed(Date)
    /// Still open, no proposal.
    case endMissing
    /// Already ended, but still flagged by the automation (its end was missing earlier, it was ended or corrected since).
    case markedByAutomation
}

public struct ReviewItem: Identifiable, Hashable, Sendable {
    public let segment: Segment
    public let day: LocalDay
    public let reason: ReviewReason
    /// The open end suggestion for this segment, if any.
    public let suggestion: TimeSuggestion?

    public var id: UUID { segment.id }

    /// The proposed end, usable with "Vorschlag übernehmen".
    public var proposedEnd: Date? {
        if case .endMissingProposed(let end) = reason { return end }
        return nil
    }
}

public enum ReviewList {
    /// Flagged, not voided, not yet dealt with; oldest first (so the first item is the first affected day).
    public static func items(segments: [Segment], suggestions: [TimeSuggestion], dismissed: Set<UUID>, calendar: DayCalendar) -> [ReviewItem] {
        var seen = Set<UUID>()
        return segments
            .filter { $0.needsReview && !$0.voided && !dismissed.contains($0.id) && seen.insert($0.id).inserted }
            .sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
            .map { segment in
                let suggestion = suggestions.first { $0.type == .end && $0.segmentId == segment.id }
                let reason: ReviewReason
                if segment.isRunning {
                    if let end = suggestion?.proposedEndedAt, end > segment.startedAt { reason = .endMissingProposed(end) } else { reason = .endMissing }
                } else {
                    reason = .markedByAutomation
                }
                return ReviewItem(segment: segment, day: calendar.day(for: segment.startedAt), reason: reason, suggestion: suggestion)
            }
    }
}

/// Segments the user has confirmed, adjusted or removed since they were flagged. Local to this device.
public struct ReviewDismissals: Sendable {
    public static let key = "review.dismissed.v1"
    public static let limit = 500
    private let suiteName: String?

    /// `nil` = standard defaults.
    public init(suiteName: String? = nil) { self.suiteName = suiteName }

    private var defaults: UserDefaults { suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard }

    public func read() -> Set<UUID> {
        Set((defaults.stringArray(forKey: Self.key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    public func add(_ id: UUID) {
        var all = defaults.stringArray(forKey: Self.key) ?? []
        guard !all.contains(id.uuidString) else { return }
        all.append(id.uuidString)
        defaults.set(Array(all.suffix(Self.limit)), forKey: Self.key)
    }
}
