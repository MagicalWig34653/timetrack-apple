import Foundation
import Observation
import TimetrackCore

/// N2: ICS calendar subscriptions of the account (`/me/calendar-feeds`). The secret link exists only in the answer of the
/// creating call; the store keeps it in `created` until the screen dismisses it and never writes it to disk.
@MainActor
@Observable
public final class CalendarFeedsStore {
    public struct Created: Equatable, Sendable {
        public let feed: CalendarFeed
        public let link: CalendarFeedLink
    }

    public private(set) var feeds: [CalendarFeed] = []
    public private(set) var hasLoaded = false
    public private(set) var isLoading = false
    public private(set) var isWorking = false
    public private(set) var created: Created?
    public var error: TimetrackError?

    /// Server limit of active subscriptions.
    public static let maximum = 10

    private let client: APIClient
    private var loadGeneration = 0

    public init(client: APIClient) { self.client = client }

    public var canCreate: Bool { feeds.count < Self.maximum }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let list = try await client.listCalendarFeeds()
            guard generation == loadGeneration else { return }
            feeds = list.sorted { $0.createdAt > $1.createdAt }
            hasLoaded = true
            error = nil
        } catch let failure as TimetrackError {
            if generation == loadGeneration, failure != .cancelled { error = failure }
        } catch {
            // not a TimetrackError: ignore
        }
    }

    /// Returns true when the feed was created (then `created` holds the one-time link).
    @discardableResult
    public func create(label: String, include: [CalendarFeedContent], expiresInDays: Int? = nil) async -> Bool {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !include.isEmpty, canCreate, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let feed = try await client.createCalendarFeed(CalendarFeedInput(label: name, include: include, expiresInDays: expiresInDays))
            guard let path = feed.path, let link = CalendarFeedLink(baseURL: client.baseURL, path: path) else {
                error = .decoding("CalendarFeed")
                await load()
                return false
            }
            created = Created(feed: feed, link: link)
            error = nil
            await load()
            return true
        } catch let failure as TimetrackError {
            error = failure
            if failure.knownCode == .tooManyCalendarFeeds { await load(); error = failure } // reload shows the full list; the message stays
            return false
        } catch {
            return false
        }
    }

    public func dismissCreated() { created = nil }

    /// Revokes a subscription; the link answers 404 from then on.
    @discardableResult
    public func revoke(_ feed: CalendarFeed) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.revokeCalendarFeed(id: feed.id)
            feeds.removeAll { $0.id == feed.id }
            error = nil
            return true
        } catch let failure as TimetrackError {
            if failure.status == 404 { feeds.removeAll { $0.id == feed.id }; return true } // already gone
            error = failure
            return false
        } catch {
            return false
        }
    }
}
