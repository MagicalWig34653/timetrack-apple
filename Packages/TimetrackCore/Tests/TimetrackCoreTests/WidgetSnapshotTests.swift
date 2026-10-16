import Foundation
import Testing
@testable import TimetrackCore

@Suite struct WidgetSnapshotTests {
    @Test func roundTripsThroughStore() {
        let suite = "test.widget.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(suiteName: suite)
        #expect(store.read() == nil)
        let snapshot = WidgetSnapshot(isRunning: true, kind: .travel, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                      todaySeconds: 3600, day: "2026-10-16", timeZone: "Europe/Berlin", updatedAt: Date(timeIntervalSince1970: 1_800_000_100))
        store.write(snapshot)
        #expect(store.read() == snapshot)
        store.clear()
        #expect(store.read() == nil)
    }

    @Test func carriesNoSecretsOrAccountData() throws {
        let data = try JSONEncoder().encode(WidgetSnapshot.empty)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(Set(keys).isSubset(of: ["isRunning", "kind", "startedAt", "todaySeconds", "day", "timeZone", "updatedAt", "targetSeconds", "balanceSeconds", "segments"]))
    }

    @Test func staleTotalIsHiddenOnAnotherDay() {
        let snapshot = WidgetSnapshot(isRunning: false, kind: .work, startedAt: nil, todaySeconds: 600, day: "2026-10-15", timeZone: "Europe/Berlin", updatedAt: .now)
        #expect(snapshot.todaySeconds(onDay: "2026-10-15") == 600)
        #expect(snapshot.todaySeconds(onDay: "2026-10-16") == nil)
    }

    @Test func totalFollowsTheWorkModelsDay() {
        // 2026-10-16 22:30 UTC is already 2026-10-17 in Berlin.
        let late = Date(timeIntervalSince1970: 1_792_189_800)
        let snapshot = WidgetSnapshot(isRunning: false, kind: .work, startedAt: nil, todaySeconds: 900, day: "2026-10-17", timeZone: "Europe/Berlin", updatedAt: late)
        #expect(snapshot.todaySeconds(at: late) == 900)
        #expect(snapshot.todaySeconds(at: late.addingTimeInterval(86_400)) == nil)
    }

    @Test func missingSuiteIsHarmless() {
        let store = WidgetSnapshotStore(suiteName: nil)
        store.write(.empty)
        #expect(store.read() == nil)
    }

    @Test func olderSnapshotWithoutNewFieldsStillDecodes() throws {
        let json = #"{"isRunning":false,"kind":"work","todaySeconds":60,"day":"2026-10-16","timeZone":"Europe\/Berlin","updatedAt":1800000000}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.targetSeconds == nil && snapshot.balanceSeconds == nil && snapshot.segments == nil)
        #expect(snapshot.todaySeconds == 60)
    }

    @Test func makeBuildsFromDayAccountAndSegments() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let now = Date(timeIntervalSince1970: 1_792_150_000)
        let first = Segment(id: UUID(), kind: .work, startedAt: now.addingTimeInterval(-7200), endedAt: now.addingTimeInterval(-3600))
        let voided = Segment(id: UUID(), kind: .travel, startedAt: now.addingTimeInterval(-9000), endedAt: now.addingTimeInterval(-8000), voided: true)
        let running = Segment(id: UUID(), kind: .school, startedAt: now.addingTimeInterval(-600))
        let day = DayEvaluation(date: "2026-10-16", targetSeconds: 28_800, evaluatedWorkSeconds: 3600, creditSeconds: 600)
        let account = TimeAccount(asOf: "2026-10-16", balanceSeconds: -1800)
        let snapshot = WidgetSnapshot.make(running: running, day: day, account: account, segments: [running, first, voided], zone: zone, now: now)
        #expect(snapshot.isRunning && snapshot.kind == .school)
        #expect(snapshot.todaySeconds == 4200 && snapshot.targetSeconds == 28_800 && snapshot.balanceSeconds == -1800)
        #expect(snapshot.segments?.map(\.kind) == [.work, .school])
        #expect(snapshot.timeZone == "Europe/Berlin")
    }

    @Test func segmentListIsCappedAndStalenessIsReported() {
        let many = (0..<20).map { WidgetSegment(kind: .work, startedAt: Date(timeIntervalSince1970: Double($0) * 100), endedAt: nil) }
        let snapshot = WidgetSnapshot(isRunning: false, kind: .work, startedAt: nil, todaySeconds: 0, day: "", timeZone: "UTC",
                                      updatedAt: Date(timeIntervalSince1970: 1000), segments: many)
        #expect(snapshot.segments?.count == WidgetSnapshot.maxSegments)
        #expect(snapshot.segments?.last == many.last)
        #expect(!snapshot.isStale(at: Date(timeIntervalSince1970: 1000 + 600)))
        #expect(snapshot.isStale(at: Date(timeIntervalSince1970: 1000 + 3600)))
    }
}
