import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

@MainActor
@Suite struct ActivityScopeTests {
    let alice = UUID()
    let bob = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func makeBase() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("activity-scope-\(UUID().uuidString)", isDirectory: true)
    }

    func interval() -> ActivityInterval {
        ActivityInterval(bundleID: "com.apple.dt.Xcode", appName: "Xcode", start: start, end: start.addingTimeInterval(600), windowTitle: "Secret")
    }

    @Test func otherAccountSeesNoDataAndStartsWithRecordingOff() {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let scope = ActivityScope(makeStorage: ActivityScope.folderStorage(base: base))
        scope.switchAccount(to: alice)
        scope.store.update { $0.enabled = true; $0.recordWindowTitles = true }
        scope.store.record([interval()], now: start)
        #expect(scope.store.settings.isRecording)
        #expect(scope.store.log.isEmpty == false)

        scope.switchAccount(to: bob)
        #expect(scope.store.settings.enabled == false)
        #expect(scope.store.settings.recordWindowTitles == false)
        #expect(scope.store.log.isEmpty)
        #expect(scope.store.rules.isEmpty)

        // Alice's data and consent are still there for her.
        scope.switchAccount(to: alice)
        #expect(scope.store.settings.enabled)
        #expect(scope.store.log.isEmpty == false)
    }

    @Test func signedOutHasNoStoreAndRecordsNothingPersistent() {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let scope = ActivityScope(makeStorage: ActivityScope.folderStorage(base: base))
        scope.switchAccount(to: alice)
        scope.store.update { $0.enabled = true }
        #expect(scope.switchAccount(to: nil))
        #expect(scope.accountId == nil)
        #expect(scope.store.settings.isRecording == false)
        #expect(scope.switchAccount(to: nil) == false)
    }

    @Test func legacyAccountlessFilesAreRemoved() throws {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let legacy = base.appendingPathComponent("log.json")
        try Data("{}".utf8).write(to: legacy)
        ActivityScope.removeLegacyFiles(in: base)
        #expect(FileManager.default.fileExists(atPath: legacy.path) == false)
    }
}
