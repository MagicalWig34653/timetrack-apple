import Foundation
import Observation
import TimetrackCore

/// Q1: the entries that need a look ("n zu prüfen"), with the reason and the fix actions. Looks back `lookbackDays` days.
/// Since contract 0.29.0 (X3) the backend clears `needsReview` on a correction of the end and on an explicit acknowledgement
/// (`PATCH needsReview: false`). Older servers never do, so what the user has dealt with is also remembered locally (`ReviewDismissals`).
@MainActor
@Observable
public final class ReviewStore {
    public private(set) var items: [ReviewItem] = []
    /// SG1: open suggestions that are not part of a flagged entry (arrival/departure proposals of the place automation).
    public private(set) var suggestions: [SuggestionEntry] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public var error: TimetrackError?
    public var onOutcome: StoreOutcomeHandler?

    public static let lookbackDays = 62

    private let client: APIClient
    private let calendar: DayCalendar
    private let dismissals: ReviewDismissals
    private var loadGeneration = 0

    public init(client: APIClient, calendar: DayCalendar, dismissals: ReviewDismissals = ReviewDismissals()) {
        self.client = client
        self.calendar = calendar
        self.dismissals = dismissals
    }

    /// Everything that needs the user's decision: flagged entries plus open suggestions ("n zu prüfen").
    public var count: Int { items.count + suggestions.count }

    /// Reads the flagged segments of the last weeks and the open suggestions. A failed read keeps the last list.
    @discardableResult
    public func load(now: Date = .now) async -> [Segment]? {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let from = now.addingTimeInterval(-Double(Self.lookbackDays) * 86_400)
            let to = now.addingTimeInterval(86_400)
            // Suggestions first: reading them lets the backend flag an automation segment left open over midnight.
            let suggestions = (try? await client.listTimeSuggestions()) ?? []
            let segments = try await client.listSegments(from: from, to: to)
            guard generation == loadGeneration else { return segments }
            let dismissed = dismissals.read()
            let fresh = ReviewList.items(segments: segments, suggestions: suggestions, dismissed: dismissed, calendar: calendar)
            if fresh != items { items = fresh }
            // An end proposal for an entry the user already dealt with (or that is listed above with it) is not asked again.
            let consumed = Set(fresh.compactMap { $0.suggestion?.id })
                .union(suggestions.filter { $0.type == .end && $0.segmentId.map(dismissed.contains) == true }.map(\.id))
            let standalone = SuggestionEntries.entries(suggestions: suggestions, consumed: consumed, segments: segments, calendar: calendar)
            if standalone != self.suggestions { self.suggestions = standalone }
            hasLoaded = true
            error = nil
            return segments
        } catch let failure as TimetrackError {
            if generation == loadGeneration, failure != .cancelled { error = failure }
        } catch {
            if generation == loadGeneration { self.error = .cancelled }
        }
        return nil
    }

    /// "Vorschlag übernehmen": ends the open entry at the proposed time.
    @discardableResult
    public func acceptProposal(_ item: ReviewItem) async -> Bool {
        guard let suggestion = item.suggestion, let end = item.proposedEnd else { return false }
        return await run {
            _ = try await self.client.acceptTimeSuggestion(id: suggestion.id, endedAt: end)
            self.dismissals.add(item.id)
        }
    }

    // MARK: - SG1: suggestions (explicit decisions only, nothing is booked silently)

    /// "Übernehmen" / "Anpassen": books the suggestion, with the user's times when they changed them.
    @discardableResult
    public func accept(_ entry: SuggestionEntry, startedAt: Date? = nil, endedAt: Date? = nil) async -> Bool {
        let start = startedAt ?? (endedAt == nil ? entry.suggestion.proposedStartedAt : nil)
        let end = endedAt ?? (startedAt == nil ? entry.suggestion.proposedEndedAt : nil)
        return await run { _ = try await self.client.acceptTimeSuggestion(id: entry.id, startedAt: start, endedAt: end) }
    }

    /// "Ablehnen": the suggestion is dropped; nothing is booked.
    @discardableResult
    public func reject(_ entry: SuggestionEntry) async -> Bool {
        await run { try await self.client.rejectTimeSuggestion(id: entry.id) }
    }

    /// Accepts every suggestion that can be accepted as proposed, one by one from the earliest. A refusal (overlap, running timer)
    /// leaves that suggestion listed and does not stop the others.
    @discardableResult
    public func acceptAll() async -> SuggestionBulkOutcome {
        var outcome = SuggestionBulkOutcome()
        for entry in suggestions where entry.canAccept {
            do {
                _ = try await client.acceptTimeSuggestion(id: entry.id, startedAt: entry.suggestion.proposedStartedAt, endedAt: entry.suggestion.proposedEndedAt)
                outcome.done += 1
            } catch let failure as TimetrackError {
                outcome.failed += 1
                if outcome.firstError == nil, failure != .cancelled { outcome.firstError = failure }
            } catch {
                outcome.failed += 1
            }
        }
        finishBulk(outcome)
        await load()
        return outcome
    }

    @discardableResult
    public func rejectAll() async -> SuggestionBulkOutcome {
        var outcome = SuggestionBulkOutcome()
        for entry in suggestions {
            do {
                try await client.rejectTimeSuggestion(id: entry.id)
                outcome.done += 1
            } catch let failure as TimetrackError {
                outcome.failed += 1
                if outcome.firstError == nil, failure != .cancelled { outcome.firstError = failure }
            } catch {
                outcome.failed += 1
            }
        }
        finishBulk(outcome)
        await load()
        return outcome
    }

    private func finishBulk(_ outcome: SuggestionBulkOutcome) {
        error = outcome.firstError
        if outcome.done > 0 { onOutcome?(.saved) } else if outcome.failed > 0 { onOutcome?(.failed) }
    }

    /// "Passt so": the entry stays as it is and the server marker is cleared (X3). An open end proposal for it is dropped so it does not
    /// come back.
    @discardableResult
    public func confirm(_ item: ReviewItem) async -> Bool {
        await run {
            if let suggestion = item.suggestion { try? await self.client.rejectTimeSuggestion(id: suggestion.id) }
            do {
                _ = try await self.client.correctSegment(id: item.segment.id, SegmentCorrection(reason: "Geprüft", acknowledgeReview: true), ifMatchVersion: item.segment.version)
            } catch let failure as TimetrackError where failure.status == 400 || failure.status == 404 {
                // Old server or nothing to acknowledge: the local memory still hides the entry.
            }
            self.dismissals.add(item.id)
        }
    }

    /// After the editor or the delete sheet closed: an entry that was saved (new version) or removed counts as dealt with.
    public func afterEditing(_ item: ReviewItem) async {
        guard let segments = await load() else { return }
        let current = segments.first { $0.id == item.id }
        guard current == nil || (current?.version ?? 0) > item.segment.version else { return }
        if let suggestion = item.suggestion { try? await client.rejectTimeSuggestion(id: suggestion.id) }
        dismissals.add(item.id)
        await load()
    }

    private func run(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            error = nil
            onOutcome?(.saved)
            await load()
            return true
        } catch let failure as TimetrackError {
            error = failure
            if failure != .cancelled { onOutcome?(.failed) }
        } catch {
            self.error = .cancelled
        }
        return false
    }
}
