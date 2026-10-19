import Foundation
import Testing
@testable import TimetrackCore

@Suite struct SystemInfoTests {
    static let member = #"{"backend":{"version":"0.1.0","revision":"0123456789abcdef","revisionShort":"0123456","buildDate":"2026-10-18T08:01:02Z","apiVersion":"0.23.0"},"pwa":{"version":"0.1.0","revision":"abc","buildDate":null}}"#
    static let admin = #"{"backend":{"version":"0.1.0","revision":"0123456789abcdef","revisionShort":"0123456","buildDate":"2026-10-18T08:01:02Z","apiVersion":"0.23.0","database":"mariadb","schemaMigrations":58,"migrationsPending":false,"uptimeSeconds":93784,"replicaId":"a1b2c3","future":1},"pwa":null}"#
    static let build = AppBuildInfo(platform: "iOS", version: "0.1.0", build: "9")

    private func decode(_ json: String) throws -> SystemInfo { try JSONCoding.makeDecoder().decode(SystemInfo.self, from: Data(json.utf8)) }

    @Test func memberAnswerHasVersionFieldsOnly() throws {
        let info = try decode(Self.member)
        #expect(info.backend.version == "0.1.0" && info.backend.apiVersion == "0.23.0" && info.backend.shortRevisionText == "0123456")
        #expect(!info.backend.hasOperationalDetails && info.backend.database == nil && info.backend.uptimeSeconds == nil)
        #expect(Self.build.supportText(backend: info) == "Timetrack iOS 0.1.0 (9), Backend 0.1.0 (0123456, 2026-10-18), API 0.23.0")
    }

    @Test func adminAnswerCarriesOperationalFields() throws {
        let info = try decode(Self.admin)
        let b = info.backend
        #expect(b.hasOperationalDetails && b.database == "mariadb" && b.schemaMigrations == 58 && b.migrationsPending == false && b.replicaId == "a1b2c3")
        #expect(SystemInfo.formatUptime(b.uptimeSeconds ?? 0) == "1 Tag 2 Std. 3 Min.")
        #expect(Self.build.supportText(backend: info).hasSuffix("API 0.23.0, mariadb"))
    }

    @Test func oldBackendWithoutEndpoint() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/system/info", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        await #expect(throws: TimetrackError.self) { try await Fixtures.client(transport).getSystemInfo() }
        #expect(Self.build.supportText(backend: nil) == "Timetrack iOS 0.1.0 (9), Backend: keine Versionsangabe verfügbar")
        #expect(SystemInfoState.unavailable.info == nil)
    }

    @Test func helpers() {
        #expect(SystemInfo.shortRevision("unknown") == nil && SystemInfo.shortRevision("") == nil && SystemInfo.shortRevision("abcdef0123") == "abcdef0")
        #expect(SystemInfo.shortDate("2026-10-18T08:01:02Z") == "2026-10-18" && SystemInfo.shortDate("garbage-date!") == nil && SystemInfo.shortDate(nil) == nil)
        #expect(SystemInfo.formatUptime(45) == "45 Sek." && SystemInfo.formatUptime(120) == "2 Min.")
        #expect(SystemInfo.formatUptime(3 * 86400) == "3 Tage 0 Std. 0 Min.")
        let local = SystemInfo(backend: .init(version: "dev", revision: "unknown", buildDate: nil, apiVersion: "0.23.0"))
        #expect(Self.build.supportText(backend: local) == "Timetrack iOS 0.1.0 (9), Backend dev, API 0.23.0")
    }
}
