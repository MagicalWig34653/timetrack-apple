import Foundation
import Testing
@testable import TimetrackCore

@Suite struct APIClientTests {
    @Test func sessionDecodesAndStoresCSRF() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok-A"))
        let client = Fixtures.client(transport)
        let session = try await client.refreshSession()
        #expect(session.account.handle == "anna")
        #expect(session.recovery == false)
        #expect(session.expiresAt != nil)
        #expect(await client.currentCSRFToken == "tok-A")
    }

    @Test func csrfHeaderOnWritesOnly() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok-B"))
        transport.enqueue("GET /api/v1/time/timer", body: "null")
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        #expect(try await client.currentTimer() == nil)
        let segment = try await client.startTimer(clientEventId: UUID(), kind: .work)
        #expect(segment.isRunning)
        let get = transport.requests(matching: "GET /api/v1/time/timer")[0]
        let post = transport.requests(matching: "POST /api/v1/time/timer/start")[0]
        #expect(get.value(forHTTPHeaderField: "X-CSRF-Token") == nil)
        #expect(post.value(forHTTPHeaderField: "X-CSRF-Token") == "tok-B")
        #expect(post.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: post.httpBody ?? Data()) as? [String: Any]
        #expect(body?["kind"] as? String == "work")
        #expect(body?["clientEventId"] is String)
        #expect(body?["placeId"] == nil)
    }

    @Test func loginResponseRefreshesCSRF() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/auth/recovery/complete", body: Fixtures.sessionJSON(csrf: "fresh", recovery: true))
        let client = Fixtures.client(transport)
        let session = try await client.recoveryComplete(recoveryId: "r1", proof: "x")
        #expect(session.recovery)
        #expect(await client.currentCSRFToken == "fresh")
    }

    @Test func staleCSRFIsRefreshedOnceAndReplayed() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/stop", status: 403, body: #"{"error":{"code":"csrf_invalid","message":"x"}}"#)
        transport.enqueue("POST /api/v1/time/timer/stop", body: Fixtures.closedSegmentJSON)
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "renewed"))
        let client = Fixtures.client(transport)
        await client.setCSRFToken("old")
        _ = try await client.stopTimer(clientEventId: UUID())
        let posts = transport.requests(matching: "POST /api/v1/time/timer/stop")
        #expect(posts.count == 2)
        #expect(posts[0].value(forHTTPHeaderField: "X-CSRF-Token") == "old")
        #expect(posts[1].value(forHTTPHeaderField: "X-CSRF-Token") == "renewed")
    }

    @Test func errorEnvelopeMapsToTypedError() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/start", status: 409, body: #"{"error":{"code":"timer_already_running","message":"läuft schon"}}"#)
        let client = Fixtures.client(transport)
        do {
            _ = try await client.startTimer(clientEventId: UUID())
            Issue.record("expected failure")
        } catch let error as TimetrackError {
            #expect(error == .api(status: 409, code: "timer_already_running", message: "läuft schon"))
            #expect(error.knownCode == .timerAlreadyRunning)
            #expect(error.germanDescription == "Es läuft bereits ein Timer.")
        }
    }

    @Test func nonJSONErrorBodyKeepsGenericCode() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/modules", status: 502, body: "<html>Bad gateway</html>")
        do {
            _ = try await Fixtures.client(transport).listModules()
            Issue.record("expected failure")
        } catch let error as TimetrackError {
            #expect(error.status == 502)
            #expect(error.code == "http_502")
            #expect(error.knownCode == nil)
            #expect(!error.germanDescription.isEmpty)
        }
    }

    @Test func everyKnownCodeHasAGermanText() {
        for code in APIErrorCode.allCases {
            let text = TimetrackError.api(status: 400, code: code.rawValue, message: "").germanDescription
            #expect(!text.isEmpty && !text.hasPrefix("error."), "missing German text for \(code.rawValue)")
        }
    }

    @Test func networkFailureIsTypedAndRetryable() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/start", error: .notConnectedToInternet)
        transport.enqueue("POST /api/v1/time/timer/start", body: Fixtures.segmentJSON)
        let client = Fixtures.client(transport)
        let eventId = UUID()
        let segment = try await retryOnNetworkError(attempts: 3, delay: .milliseconds(1)) { try await client.startTimer(clientEventId: eventId) }
        #expect(segment.isRunning)
        let posts = transport.requests(matching: "POST /api/v1/time/timer/start")
        #expect(posts.count == 2)
        #expect(posts[0].httpBody == posts[1].httpBody, "a retry must reuse the same clientEventId")
    }

    @Test func httpErrorsAreNotRetried() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/time/timer/stop", status: 409, body: #"{"error":{"code":"no_running_timer","message":"x"}}"#)
        let client = Fixtures.client(transport)
        await #expect(throws: TimetrackError.self) {
            try await retryOnNetworkError(attempts: 3, delay: .milliseconds(1)) { try await client.stopTimer(clientEventId: UUID()) }
        }
        #expect(transport.requests(matching: "POST /api/v1/time/timer/stop").count == 1)
    }

    @Test func cancellationIsReportedAsCancelled() async throws {
        let transport = MockTransport()
        transport.delay = .seconds(5)
        let client = Fixtures.client(transport)
        let task = Task { try await client.listModules() }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch {
            #expect(error is CancellationError || (error as? TimetrackError) == .cancelled)
        }
    }

    @Test func moduleDisabledNotifiesHandler() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/reports/x", status: 404, body: "")
        transport.enqueue("GET /api/v1/work-models", status: 404, body: #"{"error":{"code":"module_disabled","message":"x"}}"#)
        let client = Fixtures.client(transport)
        let flag = Flag()
        await client.setModuleDisabledHandler { flag.set() }
        _ = try? await client.listWorkModels()
        #expect(flag.value)
    }

    @Test func decodesContractPayloads() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/days/2026-10-16", body: Fixtures.dayJSON)
        transport.enqueue("GET /api/v1/time/account", body: Fixtures.accountBalanceJSON)
        transport.enqueue("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        transport.enqueue("GET /api/v1/modules", body: Fixtures.modulesJSON)
        let client = Fixtures.client(transport)

        let day = try await client.getDay("2026-10-16")
        #expect(day.targetSeconds == 27720)
        #expect(day.evaluatedWorkSeconds == 26100)
        #expect(day.provisional)
        #expect(day.mark == .unmarked)
        #expect(day.breakHints.map(\.code) == ["break_missing_30"])
        #expect(day.segments?.first?.isRunning == true)
        // fractional and plain ISO-8601 both parse
        #expect(abs((day.segments?.first?.startedAt.timeIntervalSince1970 ?? 0) - 1_792_130_820.123) < 0.001)

        let balance = try await client.getTimeAccount(asOf: "2026-10-16")
        #expect(balance.balanceSeconds == -1080)
        #expect(transport.requests(matching: "GET /api/v1/time/account")[0].url?.query == "asOf=2026-10-16")

        let models = try await client.listWorkModels()
        #expect(models.current()?.timeZone.identifier == "Europe/Berlin")
        #expect(models.first?.fixedBreaks?.first?.start == "12:00")

        let modules = ModuleSwitches(try await client.listModules())
        #expect(modules.isEnabled(.reports))
        #expect(!modules.isEnabled(.planning))
        #expect(!modules.isEnabled(.mcp))
        #expect(modules.isEnabled(.transfer), "modules the server did not list default to on")
        #expect(modules.isEnabled("fancy_future"))
    }

    @Test func correctionSendsIfMatchAndOnlyChangedFields() async throws {
        let transport = MockTransport()
        transport.enqueue("PATCH /api/v1/time/segments/33333333-3333-4333-8333-333333333333", body: Fixtures.closedSegmentJSON)
        let client = Fixtures.client(transport)
        let id = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        _ = try await client.correctSegment(id: id, SegmentCorrection(note: "x", reason: "Tippfehler"), ifMatchVersion: 3)
        let request = transport.requests(matching: "PATCH /api/v1/time/segments/33333333-3333-4333-8333-333333333333")[0]
        #expect(request.value(forHTTPHeaderField: "If-Match") == "3")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(Set(body?.keys.map { $0 } ?? []) == ["note", "reason"])
    }

    @Test func voidSendsReasonAsQueryAndSegmentListUsesInstants() async throws {
        let transport = MockTransport()
        transport.enqueue("DELETE /api/v1/time/segments/33333333-3333-4333-8333-333333333333", status: 204)
        transport.enqueue("GET /api/v1/time/segments", body: "[\(Fixtures.closedSegmentJSON)]")
        let client = Fixtures.client(transport)
        let id = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        try await client.voidSegment(id: id, reason: "Doppelt & falsch")
        let delete = transport.requests(matching: "DELETE /api/v1/time/segments/33333333-3333-4333-8333-333333333333")[0]
        #expect(delete.url?.absoluteString.hasSuffix("reason=Doppelt%20%26%20falsch") == true || delete.url?.absoluteString.hasSuffix("reason=Doppelt%20&%20falsch") == false)
        let list = try await client.listSegments(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 86400))
        #expect(list.count == 1)
        let query = transport.requests(matching: "GET /api/v1/time/segments")[0].url?.query
        #expect(query == "from=1970-01-01T00:00:00Z&to=1970-01-02T00:00:00Z")
    }

    @Test func listDaysChunksLongRanges() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/days", body: "[]")
        _ = try await Fixtures.client(transport).listDays(from: "2026-01-01", to: "2026-06-30")
        let queries = transport.requests(matching: "GET /api/v1/time/days").compactMap { $0.url?.query }
        #expect(queries == ["from=2026-01-01&to=2026-04-03", "from=2026-04-04&to=2026-06-30"])
    }

    @Test func decodingFailureIsTyped() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: #"{"unexpected":true}"#)
        await #expect(throws: TimetrackError.decoding("Session")) { try await Fixtures.client(transport).refreshSession() }
    }

    @Test func errorDescriptionsContainNoRequestSecrets() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/auth/recovery/complete", status: 401, body: #"{"error":{"code":"unauthorized","message":"nope"}}"#)
        do {
            _ = try await Fixtures.client(transport).recoveryComplete(recoveryId: "rid", proof: "TOP-SECRET-PROOF")
        } catch {
            #expect(!String(describing: error).contains("TOP-SECRET-PROOF"))
        }
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var value: Bool { lock.withLock { flag } }
}
