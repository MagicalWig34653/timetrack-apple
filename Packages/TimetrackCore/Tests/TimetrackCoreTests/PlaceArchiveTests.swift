import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// AUD3-B: archived places (contract 0.39.0): list filter, restore, fallback on older servers.

private final class NoLocation: LocationFixProviding, @unchecked Sendable {
    func currentFix() async -> LocationFix? { nil }
}

@MainActor
@Suite struct PlaceArchiveTests {
    static let activeJSON = #"{"id":"aaaaaaaa-0000-4000-8000-000000000001","name":"Büro Test","kind":"office","automationMode":"suggest","archived":false,"latitude":52.52,"longitude":13.405,"radiusMeters":150,"confirmAfterSeconds":300}"#
    static let archivedJSON = #"{"id":"aaaaaaaa-0000-4000-8000-000000000002","name":"Alte Schule Test","kind":"school","automationMode":"off","archived":true}"#
    static let restoredJSON = archivedJSON.replacingOccurrences(of: #""archived":true"#, with: #""archived":false"#)

    private func makeStore(_ transport: MockTransport) async throws -> (AutomationStore, AutomationEngine) {
        let engine = AutomationEngine(storage: InMemoryBlobStorage(), queue: AutomationEventQueue(storage: InMemoryBlobStorage(), now: { .now }),
                                      location: NoLocation(), deviceId: "ios-test", senderFactory: { nil })
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        return (AutomationStore(client: client, engine: engine, secrets: InMemorySecretStore(), deviceName: "ios-test"), engine)
    }

    @Test func listSendsTheArchivedQuery() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: "[\(Self.archivedJSON)]")
        let places = try await Fixtures.client(transport).listPlaces(archived: .archivedOnly)
        #expect(places.map(\.name) == ["Alte Schule Test"])
        #expect(transport.requests(matching: "GET /api/v1/places").first?.url?.query == "archived=true")
        transport.enqueue("GET /api/v1/places", body: "[]")
        _ = try await Fixtures.client(transport).listPlaces(archived: .all)
        #expect(transport.requests(matching: "GET /api/v1/places").last?.url?.query == "archived=all")
    }

    @Test func restoreIsAPostToTheRestorePath() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        transport.enqueue("POST /api/v1/places/aaaaaaaa-0000-4000-8000-000000000002/restore", body: Self.restoredJSON)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        let place = try await client.restorePlace(id: UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000002")!)
        #expect(!place.archived)
    }

    @Test func supportDetection() {
        #expect(PlaceArchiveSupport.isUnsupported(.api(status: 404, code: "not_found", message: "")))
        #expect(PlaceArchiveSupport.isUnsupported(.api(status: 400, code: "bad_request", message: "")))
        #expect(!PlaceArchiveSupport.isUnsupported(.api(status: 503, code: "database_unavailable", message: "")))
        #expect(!PlaceArchiveSupport.isUnsupported(.cancelled))
    }

    @Test func archivedOnlyDropsActivePlacesFromAnOldServersAnswer() throws {
        let decoder = JSONCoding.makeDecoder()
        let active = try decoder.decode(Place.self, from: Data(Self.activeJSON.utf8))
        let archived = try decoder.decode(Place.self, from: Data(Self.archivedJSON.utf8))
        #expect(PlaceArchiveSupport.archivedOnly([active, archived]).map(\.name) == ["Alte Schule Test"])
    }

    @Test func loadArchivedFillsTheListAndRestoreMovesThePlace() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: "[\(Self.archivedJSON)]")
        transport.enqueue("POST /api/v1/places/aaaaaaaa-0000-4000-8000-000000000002/restore", body: Self.restoredJSON)
        let (store, engine) = try await makeStore(transport)
        await store.loadArchived()
        #expect(store.archiveSupported == true && store.archivedPlaces.count == 1)
        let restored = await store.restore(store.archivedPlaces[0])
        #expect(restored)
        #expect(store.archivedPlaces.isEmpty)
        #expect(store.places.map(\.name) == ["Alte Schule Test"])
        #expect(await engine.snapshot.places.count == 1)
    }

    @Test func olderServerHidesTheArchive() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", status: 400, body: #"{"error":{"code":"bad_request","message":"x"}}"#)
        let (store, _) = try await makeStore(transport)
        await store.loadArchived()
        #expect(store.archiveSupported == false && store.archivedPlaces.isEmpty && store.error == nil)
    }

    @Test func networkFailureDoesNotHideTheArchive() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", error: .notConnectedToInternet)
        let (store, _) = try await makeStore(transport)
        await store.loadArchived()
        #expect(store.archiveSupported == nil && store.error != nil)
    }

    @Test func failedRestoreKeepsThePlaceArchived() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/places", body: "[\(Self.archivedJSON)]")
        transport.enqueue("POST /api/v1/places/aaaaaaaa-0000-4000-8000-000000000002/restore", status: 500, body: #"{"error":{"code":"internal","message":"x"}}"#)
        let (store, _) = try await makeStore(transport)
        await store.loadArchived()
        #expect(await store.restore(store.archivedPlaces[0]) == false)
        #expect(store.archivedPlaces.count == 1 && store.places.isEmpty)
    }
}
