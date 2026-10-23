import Foundation
import Observation
import TimetrackCore

/// Q1: the entries that need a look ("n zu prüfen"), with the reason and the fix actions. Looks back `lookbackDays` days.
/// The backend never clears `needsReview` itself, so what the user has dealt with is remembered locally (`ReviewDismissals`).
@MainActor
@Observable
public final class ReviewStore {
    public private(set) var items: [ReviewItem] = []
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

    public var count: Int { items.count }

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
            let fresh = ReviewList.items(segments: segments, suggestions: suggestions, dismissed: dismissals.read(), calendar: calendar)
            if fresh != items { items = fresh }
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

    /// "Passt so": the entry stays as it is. An open end proposal for it is dropped so it does not come back.
    @discardableResult
    public func confirm(_ item: ReviewItem) async -> Bool {
        await run {
            if let suggestion = item.suggestion { try? await self.client.rejectTimeSuggestion(id: suggestion.id) }
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
