import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// AUD3-A: trigger links (contract 0.26.0, ADR-0027). Synthetic data only.

private let linkId1 = "77777777-7777-4777-8777-777777777771"
private let linkId2 = "77777777-7777-4777-8777-777777777772"
private let placeId = "88888888-8888-4888-8888-888888888881"

private func linkJSON(id: String, label: String = "Desk tag", actions: String = #"["start","stop"]"#, place: String? = nil,
                      kind: String = "work", withSecret: Bool = false, lastAction: String? = nil, created: String = "2026-10-26T08:00:00Z") -> String {
    let secret = withSecret ? #","token":"tok123","path":"/t/tok123""# : ""
    let last = lastAction.map { #","lastUsedAt":"2026-10-27T08:00:00Z","lastAction":"\#($0)""# } ?? ""
    let placeJSON = place.map { #""\#($0)""# } ?? "null"
    return #"{"id":"\#(id)","label":"\#(label)","actions":\#(actions),"placeId":\#(placeJSON),"kind":"\#(kind)","createdAt":"\#(created)","expiresAt":null\#(last)\#(secret)}"#
}

private let placesJSON = #"[{"id":"\#(placeId)","name":"Office","kind":"work","automationMode":"off","archived":false},{"id":"88888888-8888-4888-8888-888888888882","name":"Old","kind":"other","automationMode":"off","archived":true}]"#

@Suite("AUD3-A trigger link models") struct TriggerLinkModelTests {
    @Test func addressesPrefixTheServerPerAction() throws {
        let set = try #require(TriggerLinkAddresses(baseURL: URL(string: "https://timetrack.example.org")!, path: "/t/tok123", actions: [.start, .toggle]))
        #expect(set.entries.map(\.url.absoluteString) == ["https://timetrack.example.org/t/tok123/start", "https://timetrack.example.org/t/tok123/toggle"])
    }

    @Test func addressesKeepPortAndPathPrefix() throws {
        let set = try #require(TriggerLinkAddresses(baseURL: URL(string: "http://localhost:18090/tt/")!, path: "/t/a", actions: [.stop]))
        #expect(set.entries.first?.url.absoluteString == "http://localhost:18090/tt/t/a/stop")
    }

    @Test func addressesRejectForeignPathsAndEmptyActions() {
        let base = URL(string: "https://x.example")!
        #expect(TriggerLinkAddresses(baseURL: base, path: "/api/v1/me", actions: [.start]) == nil)
        #expect(TriggerLinkAddresses(baseURL: base, path: "/t/a", actions: []) == nil)
    }

    @Test func linkDecodesWithAndWithoutTheSecretAndKeepsUnknownActions() throws {
        let decoder = JSONCoding.makeDecoder()
        let listed = try decoder.decode(TriggerLink.self, from: Data(linkJSON(id: linkId1, actions: #"["start","future","toggle"]"#, lastAction: "toggle").utf8))
        #expect(listed.token == nil && listed.path == nil)
        #expect(listed.actionNames == ["start", "future", "toggle"])
        #expect(listed.actions == [.start, .toggle])
        #expect(listed.actionSummary == "Start, Umschalten")
        #expect(listed.lastActionTitle == "Umschalten")
        let created = try decoder.decode(TriggerLink.self, from: Data(linkJSON(id: linkId1, withSecret: true).utf8))
        #expect(created.token == "tok123")
        #expect(created.path == "/t/tok123")
    }

    @Test func unknownKindFallsBackLeniently() throws {
        let link = try JSONCoding.makeDecoder().decode(TriggerLink.self, from: Data(linkJSON(id: linkId1, kind: "teleport").utf8))
        #expect(link.kind == .unknown)
    }

    @Test func inputTrimsCapsOrdersAndOmitsNulls() throws {
        let input = TriggerLinkInput(label: "  " + String(repeating: "x", count: 100) + "  ", actions: [.toggle, .start, .start], kind: .unknown)
        #expect(input.label.count == 80)
        #expect(input.actions == [.start, .toggle])
        #expect(input.kind == .work, "an unknown kind is never sent")
        let json = try #require(try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(input)) as? [String: Any])
        #expect(json["actions"] as? [String] == ["start", "toggle"])
        #expect(json["kind"] as? String == "work")
        #expect(json["placeId"] == nil && json["expiresInDays"] == nil)
        let bound = TriggerLinkInput(label: "a", actions: [.stop], placeId: UUID(uuidString: placeId), kind: .travel, expiresInDays: 30)
        let boundJSON = try #require(try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(bound)) as? [String: Any])
        #expect((boundJSON["placeId"] as? String)?.lowercased() == placeId)
        #expect(boundJSON["expiresInDays"] as? Int == 30)
    }

    @Test func tooManyLinksHasGermanText() {
        let error = TimetrackError.api(status: 409, code: "too_many_trigger_links", message: "x")
        #expect(error.knownCode == .tooManyTriggerLinks)
        #expect(error.germanDescription != "error.too_many_trigger_links")
        #expect(error.germanDescription != TimetrackError.api(status: 400, code: "zzz", message: "").germanDescription)
    }
}

@Suite("AUD3-A trigger links store") @MainActor struct TriggerLinksStoreTests {
    @Test func loadsNewestFirstWithPlaces() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/trigger-links", body: "[\(linkJSON(id: linkId1, label: "old")),\(linkJSON(id: linkId2, label: "new", place: placeId, created: "2026-10-27T08:00:00Z"))]")
        transport.enqueue("GET /api/v1/places", body: placesJSON)
        let store = TriggerLinksStore(client: Fixtures.client(transport))
        await store.load()
        #expect(store.links.map(\.label) == ["new", "old"])
        #expect(store.hasLoaded)
        #expect(store.selectablePlaces.map(\.name) == ["Office"], "archived places cannot be chosen")
        #expect(store.placeDescription(for: store.links[0]) == "Ort: Office")
        #expect(store.placeDescription(for: store.links[1]) == "ohne Ortsbindung")
    }

    @Test func boundPlaceThatVanishedIsLabelled() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/trigger-links", body: "[\(linkJSON(id: linkId1, place: "88888888-8888-4888-8888-8888888888ff"))]")
        transport.enqueue("GET /api/v1/places", body: "[]")
        let store = TriggerLinksStore(client: Fixtures.client(transport))
        await store.load()
        #expect(store.placeDescription(for: store.links[0]) == "Ort: (nicht mehr vorhanden)")
    }

    @Test func createKeepsTheOneTimeAddressesOnlyInMemory() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/me/trigger-links", status: 201, body: linkJSON(id: linkId1, withSecret: true))
        transport.enqueue("GET /api/v1/me/trigger-links", body: "[\(linkJSON(id: linkId1))]")
        transport.enqueue("GET /api/v1/places", body: "[]")
        let store = TriggerLinksStore(client: Fixtures.client(transport))
        #expect(await store.create(label: "Desk tag", actions: [.start, .stop]))
        #expect(store.created?.addresses.entries.map(\.url.absoluteString) == ["http://localhost:18090/t/tok123/start", "http://localhost:18090/t/tok123/stop"])
        #expect(store.links.count == 1)
        #expect(store.links.first?.token == nil, "the list never carries the secret")
        let sent = try #require(transport.requests(matching: "POST /api/v1/me/trigger-links").first)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(body["label"] as? String == "Desk tag")
        #expect(body["actions"] as? [String] == ["start", "stop"])
        #expect(body["kind"] as? String == "work")
        #expect(body["placeId"] == nil && body["expiresInDays"] == nil)
        store.dismissCreated()
        #expect(store.created == nil)
    }

    @Test func createValidatesLocally() async {
        let transport = MockTransport()
        let store = TriggerLinksStore(client: Fixtures.client(transport))
        #expect(await store.create(label: "  ", actions: [.start]) == false)
        #expect(await store.create(label: "x", actions: []) == false)
        #expect(await store.create(label: "x", actions: [.start], expiresInDays: 0) == false)
        #expect(await store.create(label: "x", actions: [.start], expiresInDays: 731) == false)
        #expect(transport.requests.isEmpty)
    }

    @Test func twentyLinksBlockCreationLocallyAndTheServerLimitIsMapped() async {
        let ids = (0..<20).map { String(format: "77777777-7777-4777-8777-7777777777%02d", $0 + 10) }
        let list = "[\(ids.map { linkJSON(id: $0) }.joined(separator: ","))]"
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/trigger-links", body: list)
        transport.enqueue("GET /api/v1/places", body: "[]")
        let store = TriggerLinksStore(client: Fixtures.client(transport))
        await store.load()
        #expect(store.canCreate == false)
        #expect(await store.create(label: "x", actions: [.start]) == false)
        #expect(transport.requests(matching: "POST /api/v1/me/trigger-links").isEmpty)

        let other = MockTransport()
        other.enqueue("POST /api/v1/me/trigger-links", status: 409, body: #"{"error":{"code":"too_many_trigger_links","message":"x"}}"#)
        other.enqueue("GET /api/v1/me/trigger-links", body: list)
        other.enqueue("GET /api/v1/places", body: "[]")
        let racing = TriggerLinksStore(client: Fixtures.client(other))
        #expect(await racing.create(label: "x", actions: [.start]) == false)
        #expect(racing.error?.knownCode == .tooManyTriggerLinks)
        #expect(racing.links.count == 20)
    }

    @Test func revokeRemovesTheLinkAndTreats404AsGone() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/trigger-links", body: "[\(linkJSON(id: linkId1)),\(linkJSON(id: linkId2, created: "2026-10-27T08:00:00Z"))]")
        transport.enqueue("GET /api/v1/places", body: "[]")
        transport.enqueue("DELETE /api/v1/me/trigger-links/\(linkId2)", status: 204)
        transport.enqueue("DELETE /api/v1/me/trigger-links/\(linkId1)", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let store = TriggerLinksStore(client: Fixtures.client(transport))
        await store.load()
        #expect(await store.revoke(store.links[0]))
        #expect(store.links.count == 1)
        #expect(await store.revoke(store.links[0]))
        #expect(store.links.isEmpty)
    }

    @Test func revokeFailureKeepsTheLink() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/me/trigger-links", body: "[\(linkJSON(id: linkId1))]")
        transport.enqueue("GET /api/v1/places", body: "[]")
        transport.enqueue("DELETE /api/v1/me/trigger-links/\(linkId1)", error: .notConnectedToInternet)
        let store = TriggerLinksStore(client: Fixtures.client(transport))
        await store.load()
        #expect(await store.revoke(store.links[0]) == false)
        #expect(store.links.count == 1)
        #expect(store.error != nil)
    }
}
