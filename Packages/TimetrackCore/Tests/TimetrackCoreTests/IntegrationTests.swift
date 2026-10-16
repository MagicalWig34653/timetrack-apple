import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// Runs only against a THROWAWAY backend: set TT_INTEGRATION_URL (e.g. http://localhost:18091) and
/// TT_INTEGRATION_COOKIE_FILE (file holding a tt_session value). Skipped otherwise.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TT_INTEGRATION_URL"] != nil))
@MainActor struct IntegrationTests {
    @Test func timerRoundTripAgainstRealBackend() async throws {
        let env = ProcessInfo.processInfo.environment
        let url = try AuthService.normalizeServerURL(try #require(env["TT_INTEGRATION_URL"]))
        #expect(url.port != 18080, "never the live instance")
        let cookie = try String(contentsOfFile: try #require(env["TT_INTEGRATION_COOKIE_FILE"]), encoding: .utf8)
        let auth = AuthService(secrets: InMemorySecretStore(), transport: URLSessionTransport())
        let context = try await auth.signInWithSessionCookie(server: url, cookieValue: cookie)
        let client = context.client
        #expect(!context.session.recovery)

        let modules = try await client.listModules()
        #expect(modules.count >= 5)
        _ = try await client.listWorkModels()

        #expect(try await client.currentTimer() == nil)
        let started = try await client.startTimer(clientEventId: UUID(), kind: .work)
        #expect(started.isRunning)
        let again = try? await client.startTimer(clientEventId: UUID())
        #expect(again == nil, "second start must be refused (timer_already_running)")
        let today = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!).day(for: .now)
        let day = try await client.getDay(today)
        #expect(day.provisional)
        let stopped = try await client.stopTimer(clientEventId: UUID())
        #expect(stopped.endedAt != nil)

        let created = try await client.createSegment(SegmentInput(kind: .school, startedAt: .now.addingTimeInterval(-7200), endedAt: .now.addingTimeInterval(-3600), note: "integration"))
        let fixed = try await client.correctSegment(id: created.id, SegmentCorrection(note: "korrigiert", reason: "Test"), ifMatchVersion: created.version)
        #expect(fixed.version > created.version)
        do {
            _ = try await client.correctSegment(id: created.id, SegmentCorrection(note: "x", reason: "stale"), ifMatchVersion: created.version)
            Issue.record("stale version must be refused")
        } catch let error as TimetrackError {
            #expect(error.knownCode == .staleVersion)
        }
        try await client.voidSegment(id: created.id, reason: "Test aufgeräumt")
        _ = try await client.getTimeAccount(asOf: today)
        let days = try await client.listDays(from: LocalDays.adding(-120, to: today)!, to: today)
        #expect(days.count == 121, "chunked range over 93 days")

        // Store layer
        let model = AppModel(auth: auth)
        await model.restore()
        #expect(model.phase == .signedIn)
        await model.today?.start()
        #expect(model.today?.running != nil)
        await model.today?.stop()
        #expect(model.today?.running == nil)
        #expect(model.today?.error == nil)

        await auth.signOut()
    }
}
