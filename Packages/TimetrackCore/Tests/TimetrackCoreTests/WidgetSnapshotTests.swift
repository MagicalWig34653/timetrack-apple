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
        #expect(Set(keys).isSubset(of: ["isRunning", "kind", "startedAt", "todaySeconds", "day", "timeZone", "updatedAt"]))
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
}
