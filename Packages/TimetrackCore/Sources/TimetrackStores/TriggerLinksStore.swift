import Foundation
import Observation
import TimetrackCore

/// AUD3-A: trigger links of the account (`/me/trigger-links`). The secret addresses exist only in the answer of the
/// creating call; the store keeps them in `created` until the screen dismisses them and never writes them to disk.
@MainActor
@Observable
public final class TriggerLinksStore {
    public struct Created: Equatable, Sendable {
        public let link: TriggerLink
        public let addresses: TriggerLinkAddresses
    }

    public private(set) var links: [TriggerLink] = []
    /// Places for the binding picker and the list rows (archived ones are kept so a bound link still shows its name).
    public private(set) var places: [Place] = []
    public private(set) var hasLoaded = false
    public private(set) var isLoading = false
    public private(set) var isWorking = false
    public private(set) var created: Created?
    public var error: TimetrackError?

    /// Server limit of active links.
    public static let maximum = 20

    private let client: APIClient
    private var loadGeneration = 0

    public init(client: APIClient) { self.client = client }

    public var canCreate: Bool { links.count < Self.maximum }

    /// Places that can be chosen for a new link.
    public var selectablePlaces: [Place] { places.filter { !$0.archived } }

    /// Row text about the place binding.
    public func placeDescription(for link: TriggerLink) -> String {
        guard let placeId = link.placeId else { return "ohne Ortsbindung" }
        guard let place = places.first(where: { $0.id == placeId }) else { return "Ort: (nicht mehr vorhanden)" }
        return "Ort: \(place.name)"
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            async let listed = client.listTriggerLinks()
            async let placeList = client.listPlaces()
            let (list, placesResult) = try await (listed, placeList)
            guard generation == loadGeneration else { return }
            links = list.sorted { $0.createdAt > $1.createdAt }
            places = placesResult
            hasLoaded = true
            error = nil
        } catch let failure as TimetrackError {
            if generation == loadGeneration, failure != .cancelled { error = failure }
        } catch {
            // not a TimetrackError: ignore
        }
    }

    /// Returns true when the link was created (then `created` holds the one-time addresses).
    @discardableResult
    public func create(label: String, actions: [TriggerAction], placeId: UUID? = nil, kind: SegmentKind = .work, expiresInDays: Int? = nil) async -> Bool {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !actions.isEmpty, canCreate, !isWorking else { return false }
        if let days = expiresInDays, !TriggerLinkInput.expiryRange.contains(days) { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let input = TriggerLinkInput(label: name, actions: actions, placeId: placeId, kind: kind, expiresInDays: expiresInDays)
            let link = try await client.createTriggerLink(input)
            guard let path = link.path, let addresses = TriggerLinkAddresses(baseURL: client.baseURL, path: path, actions: link.actions) else {
                error = .decoding("TriggerLink")
                await load()
                return false
            }
            created = Created(link: link, addresses: addresses)
            error = nil
            await load()
            return true
        } catch let failure as TimetrackError {
            error = failure
            if failure.knownCode == .tooManyTriggerLinks { await load(); error = failure } // reload shows the full list; the message stays
            return false
        } catch {
            return false
        }
    }

    public func dismissCreated() { created = nil }

    /// Revokes a link; it answers 404 from then on.
    @discardableResult
    public func revoke(_ link: TriggerLink) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.revokeTriggerLink(id: link.id)
            links.removeAll { $0.id == link.id }
            error = nil
            return true
        } catch let failure as TimetrackError {
            if failure.status == 404 { links.removeAll { $0.id == link.id }; return true } // already gone
            error = failure
            return false
        } catch {
            return false
        }
    }
}
