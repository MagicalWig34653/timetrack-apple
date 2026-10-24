import Foundation

// SG1: the automation's open suggestions as a list the user decides on. Nothing here ever books anything: a suggestion becomes an
// entry only through an explicit accept (`POST /time/suggestions/{id}/accept`) after the user pressed the button.
//
// Where suggestions come from (backend `AutomationService`): "start" = arrival at a place in suggestion mode (propose to start the
// timer at the arrival time); "end" with a place = the user left the place while a timer runs (propose to stop at the departure);
// "end" without a place = a segment the automation started whose departure never arrived (also flagged `needsReview`, shown as a
// Q1 `ReviewItem` and therefore NOT listed again here).

/// One open suggestion that is not already part of a flagged entry in the Q1 review list.
public struct SuggestionEntry: Identifiable, Hashable, Sendable {
    public let suggestion: TimeSuggestion
    /// The entry an "end" suggestion refers to, when it is known (looked up in the recent entries).
    public let segment: Segment?
    public let day: LocalDay

    public var id: UUID { suggestion.id }
    public var kind: TimeSuggestion.Kind { suggestion.type }
    public var placeId: UUID? { suggestion.placeId }

    /// The moment the suggestion is about; used for ordering and the day heading.
    public var anchor: Date { suggestion.proposedStartedAt ?? suggestion.proposedEndedAt ?? suggestion.createdAt }

    /// Whether "Übernehmen" is offered as is: the proposal carries the time it needs (and an end lies after the entry's start).
    public var canAccept: Bool {
        switch kind {
        case .start:
            return suggestion.proposedStartedAt != nil
        case .end:
            guard let end = suggestion.proposedEndedAt else { return false }
            if let start = segment?.startedAt { return end > start }
            return true
        case .unknown:
            return false
        }
    }

    /// "Anpassen" needs a kind it understands.
    public var canAdjust: Bool { kind != .unknown }

    public init(suggestion: TimeSuggestion, segment: Segment? = nil, day: LocalDay) {
        self.suggestion = suggestion
        self.segment = segment
        self.day = day
    }
}

public enum SuggestionEntries {
    /// Open suggestions minus those `consumed` by Q1 review items, in chronological order (so a bulk accept proceeds from the earliest).
    public static func entries(suggestions: [TimeSuggestion], consumed: Set<UUID>, segments: [Segment], calendar: DayCalendar) -> [SuggestionEntry] {
        let byId = Dictionary(segments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        return suggestions
            .filter { !consumed.contains($0.id) && seen.insert($0.id).inserted }
            .map { suggestion in
                let anchor = suggestion.proposedStartedAt ?? suggestion.proposedEndedAt ?? suggestion.createdAt
                return SuggestionEntry(suggestion: suggestion, segment: suggestion.segmentId.flatMap { byId[$0] }, day: calendar.day(for: anchor))
            }
            .sorted { ($0.anchor, $0.id.uuidString) < ($1.anchor, $1.id.uuidString) }
    }
}

/// Editable times for "Anpassen". A start suggestion may end right away (a finished past block) or stay a running timer.
public struct SuggestionDraft: Equatable, Sendable {
    public var start: Date
    public var end: Date
    /// Start suggestions only: also set an end (otherwise the timer runs from `start`).
    public var hasEnd: Bool
    public let kind: TimeSuggestion.Kind
    /// The start of the entry an "end" suggestion closes; the new end must lie after it.
    public let segmentStart: Date?

    public init(entry: SuggestionEntry, now: Date = .now) {
        kind = entry.kind
        segmentStart = entry.segment?.startedAt
        let proposedStart = entry.suggestion.proposedStartedAt
        let proposedEnd = entry.suggestion.proposedEndedAt
        start = proposedStart ?? entry.segment?.startedAt ?? now
        hasEnd = entry.kind == .start && proposedEnd != nil
        end = proposedEnd ?? min(now, start.addingTimeInterval(3_600)) // one hour after the start, never in the future
    }

    /// Times lie in the past or now, and an end lies after its start.
    public func isValid(now: Date = .now) -> Bool {
        switch kind {
        case .start:
            guard start <= now else { return false }
            return !hasEnd || (end > start && end <= now)
        case .end:
            if let segmentStart, end <= segmentStart { return false }
            return end <= now
        case .unknown: return false
        }
    }

    /// Values sent with the accept call. Only what the user can change for the kind.
    public var overrides: (startedAt: Date?, endedAt: Date?) {
        switch kind {
        case .start: (start, hasEnd ? end : nil)
        case .end: (nil, end)
        case .unknown: (nil, nil)
        }
    }
}

/// Result of a bulk accept or reject: how many went through and the first problem (the rest are still listed).
public struct SuggestionBulkOutcome: Equatable, Sendable {
    public var done = 0
    public var failed = 0
    public var firstError: TimetrackError?

    public init(done: Int = 0, failed: Int = 0, firstError: TimetrackError? = nil) {
        self.done = done
        self.failed = failed
        self.firstError = firstError
    }
}
