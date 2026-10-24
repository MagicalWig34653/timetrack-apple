import Foundation
import Observation
import TimetrackCore

/// Where the activity data lives: four small JSON documents in the app container. Never the App Group, never the network.
public struct ActivityStorage: Sendable {
    public var settings: BlobStorage
    public var rules: BlobStorage
    public var log: BlobStorage
    public var dismissed: BlobStorage

    public init(settings: BlobStorage, rules: BlobStorage, log: BlobStorage, dismissed: BlobStorage) {
        self.settings = settings
        self.rules = rules
        self.log = log
        self.dismissed = dismissed
    }

    public static func files(in folder: URL) -> ActivityStorage {
        ActivityStorage(settings: FileBlobStorage(url: folder.appendingPathComponent("settings.json")),
                        rules: FileBlobStorage(url: folder.appendingPathComponent("rules.json")),
                        log: FileBlobStorage(url: folder.appendingPathComponent("log.json")),
                        dismissed: FileBlobStorage(url: folder.appendingPathComponent("dismissed.json")))
    }

    public static func inMemory() -> ActivityStorage {
        ActivityStorage(settings: InMemoryBlobStorage(), rules: InMemoryBlobStorage(), log: InMemoryBlobStorage(), dismissed: InMemoryBlobStorage())
    }
}

/// M2: the local activity log, its settings and mapping rules. The Mac app feeds it; the "Aktivität" view and the suggestions read it.
@MainActor
@Observable
public final class ActivityStore {
    public private(set) var settings: ActivitySettings
    public private(set) var rules: [ActivityRule]
    public private(set) var log: ActivityLog
    public private(set) var dismissed: Set<String>

    @ObservationIgnored private let storage: ActivityStorage
    @ObservationIgnored private var lastPrune: Date?

    public init(storage: ActivityStorage) {
        self.storage = storage
        settings = Self.decode(ActivitySettings.self, storage.settings) ?? ActivitySettings()
        rules = Self.decode([ActivityRule].self, storage.rules) ?? []
        log = Self.decode(ActivityLog.self, storage.log) ?? ActivityLog()
        dismissed = Set(Self.decode([String].self, storage.dismissed) ?? [])
    }

    // MARK: Settings

    public func update(now: Date = .now, _ change: (inout ActivitySettings) -> Void) {
        let before = settings
        var copy = settings
        change(&copy)
        settings = copy.clamped
        Self.encode(settings, storage.settings)
        if before.recordWindowTitles, !settings.recordWindowTitles { log.stripTitles(); saveLog() } // switching titles off removes the stored ones
        if settings.retentionDays < before.retentionDays { prune(now: now) }
    }

    /// Adds an app to the exclude list and forgets what was recorded for it.
    public func exclude(bundleID: String) {
        update { if !$0.excludedBundleIDs.contains(bundleID) { $0.excludedBundleIDs.append(bundleID) } }
        if log.remove(bundleID: bundleID) > 0 { saveLog() }
    }

    public func include(bundleID: String) {
        update { $0.excludedBundleIDs.removeAll { $0 == bundleID } }
    }

    // MARK: Log

    public func record(_ closed: [ActivityInterval], now: Date = .now) {
        guard !closed.isEmpty else { return }
        for interval in closed where !settings.isExcluded(interval.bundleID) { log.append(interval) }
        if lastPrune.map({ now.timeIntervalSince($0) > 3600 }) ?? true { prune(now: now) } else { saveLog() }
    }

    /// Removes intervals older than the retention window (also called once an hour while recording and at launch).
    public func prune(now: Date) {
        lastPrune = now
        log.prune(retentionDays: settings.retentionDays, now: now)
        saveLog()
    }

    /// "Alle Aktivitätsdaten löschen": the log and the dismissed suggestions. Settings and rules stay.
    public func deleteAllData() {
        log.removeAll()
        dismissed = []
        saveLog()
        Self.encode(Array(dismissed), storage.dismissed)
    }

    public func intervals(from: Date, to: Date) -> [ActivityInterval] { log.intervals(from: from, to: to) }

    // MARK: Rules and suggestions

    public func saveRule(_ rule: ActivityRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule } else { rules.append(rule) }
        Self.encode(rules, storage.rules)
    }

    public func deleteRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
        Self.encode(rules, storage.rules)
    }

    public func suggestions(segments: [Segment], from: Date, to: Date, now: Date = .now) -> [ActivitySuggestion] {
        ActivitySuggestionEngine.suggestions(intervals: log.intervals(from: from, to: to), rules: rules, segments: segments, dismissed: dismissed, now: now)
    }

    public func dismiss(_ suggestionID: String) {
        dismissed.insert(suggestionID)
        Self.encode(Array(dismissed), storage.dismissed)
    }

    // MARK: Persistence

    private func saveLog() { Self.encode(log, storage.log) }

    private static func decode<T: Decodable>(_ type: T.Type, _ storage: BlobStorage) -> T? {
        storage.load().flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T, _ storage: BlobStorage) {
        if let data = try? JSONEncoder().encode(value) { storage.save(data) }
    }
}
