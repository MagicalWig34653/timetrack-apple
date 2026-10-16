import Foundation
import Testing
@testable import TimetrackCore

@Suite struct PreferencesTests {
    private static let prefsJSON = #"{"accent":"orange","accentCustomHex":null,"colorScheme":"dark","updatedAt":"2026-10-16T21:04:05Z"}"#

    @Test func decodesAndToleratesFutureFieldsAndMissingValues() throws {
        let full = try JSONCoding.makeDecoder().decode(Preferences.self, from: Data(##"{"accent":"custom","accentCustomHex":"#AB12CD","colorScheme":"light","updatedAt":"2026-10-16T21:04:05Z","density":"compact"}"##.utf8))
        #expect(full.accentPreset == .custom && full.customHex == "#AB12CD" && full.scheme == .light && full.updatedAt != nil)
        // Never saved: server answers defaults without updatedAt; accentCustomHex may be absent.
        let unset = try JSONCoding.makeDecoder().decode(Preferences.self, from: Data(#"{"accent":"blue","colorScheme":"system"}"#.utf8))
        #expect(unset.isUnset && unset.accentCustomHex == nil && unset.accentPreset == .blue)
        // Unknown future ids show as defaults and are flagged.
        let future = try JSONCoding.makeDecoder().decode(Preferences.self, from: Data(#"{"accent":"magenta","colorScheme":"twilight","updatedAt":"2026-10-16T21:04:05.250Z"}"#.utf8))
        #expect(future.accentPreset == .blue && future.hasUnknownAccent && future.scheme == .system && future.hasUnknownScheme)
    }

    @Test func sessionCarriesPreferencesAndOldServersDoNot() async throws {
        let transport = MockTransport()
        let withPrefs = #"{"account":{"id":"11111111-1111-4111-8111-111111111111","handle":"anna","displayName":"Anna","role":"member","preferences":\#(Self.prefsJSON)},"csrfToken":"c","recovery":false}"#
        transport.enqueue("GET /api/v1/auth/session", body: withPrefs)
        let session = try await Fixtures.client(transport).refreshSession()
        #expect(session.account.preferences?.accent == "orange")
        #expect(session.account.preferences?.scheme == .dark)

        let old = MockTransport()
        old.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON())
        #expect(try await Fixtures.client(old).refreshSession().account.preferences == nil)

        // A malformed preferences block never breaks sign-in.
        let broken = MockTransport()
        broken.enqueue("GET /api/v1/auth/session", body: withPrefs.replacingOccurrences(of: #""accent":"orange""#, with: #""accent":42"#))
        #expect(try await Fixtures.client(broken).refreshSession().account.preferences == nil)
    }

    @Test func getAndPatchBodies() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        transport.enqueue("GET /api/v1/me/preferences", body: Self.prefsJSON)
        transport.enqueue("PATCH /api/v1/me/preferences", body: ##"{"accent":"custom","accentCustomHex":"#AB12CD","colorScheme":"light","updatedAt":"2026-10-16T22:00:00Z"}"##)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        #expect(try await client.getPreferences().accent == "orange")
        let updated = try await client.updatePreferences(PreferencesPatch(accent: "custom", colorScheme: "light", customHex: .set("#AB12CD")))
        #expect(updated.customHex == "#AB12CD")
        let request = transport.requests(matching: "PATCH /api/v1/me/preferences")[0]
        #expect(request.value(forHTTPHeaderField: "X-CSRF-Token") == "tok")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(body?["accent"] as? String == "custom" && body?["accentCustomHex"] as? String == "#AB12CD" && body?["colorScheme"] as? String == "light")
    }

    @Test func patchEncodesOnlySetKeysAndExplicitNull() throws {
        func json(_ patch: PreferencesPatch) throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: try JSONCoding.makeEncoder().encode(patch)) as? [String: Any])
        }
        let preset = try json(PreferencesPatch(accent: "teal", colorScheme: "system"))
        #expect(Set(preset.keys) == ["accent", "colorScheme"])
        let cleared = try json(PreferencesPatch(accent: "blue", customHex: .clear))
        #expect(cleared["accentCustomHex"] is NSNull && cleared["colorScheme"] == nil)
        #expect(try json(PreferencesPatch()).isEmpty)
    }

    @Test func badRequestAndForbiddenAreReported() async throws {
        let transport = MockTransport()
        transport.enqueue("PATCH /api/v1/me/preferences", status: 400, body: #"{"error":{"code":"bad_request","message":"accentCustomHex requires accent custom"}}"#)
        let client = Fixtures.client(transport)
        await #expect(throws: TimetrackError.self) { try await client.updatePreferences(PreferencesPatch(accent: "blue", customHex: .set("#AB12CD"))) }
        do { _ = try await client.updatePreferences(PreferencesPatch(accent: "blue")) } catch let error as TimetrackError {
            #expect(error.status == 400 && error.knownCode == .badRequest)
        }
        let recovery = MockTransport()
        recovery.enqueue("PATCH /api/v1/me/preferences", status: 403, body: #"{"error":{"code":"recovery_session_restricted","message":"x"}}"#)
        do { _ = try await Fixtures.client(recovery).updatePreferences(PreferencesPatch(accent: "blue")) } catch let error as TimetrackError {
            #expect(error.status == 403 && error.knownCode == .recoverySessionRestricted)
        }
    }

    @Test func hexNormalisation() {
        #expect(Preferences.normalizedHex("#ab12cd") == "#AB12CD")
        #expect(Preferences.normalizedHex("ab12cd") == nil)
        #expect(Preferences.normalizedHex("#12345") == nil)
        #expect(Preferences.normalizedHex("#GG0000") == nil)
    }
}

// MARK: - Reconcile

private final class FakeService: PreferencesService, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [PreferencesPatch] = []
    private var _failures: [TimetrackError] = []
    var sent: [PreferencesPatch] { lock.withLock { _sent } }
    func failNext(_ errors: TimetrackError...) { lock.withLock { _failures += errors } }

    func getPreferences() async throws -> Preferences { Preferences() }

    func updatePreferences(_ patch: PreferencesPatch) async throws -> Preferences {
        try lock.withLock {
            _sent.append(patch)
            if !_failures.isEmpty { throw _failures.removeFirst() }
        }
        return Preferences(accent: patch.accent ?? "blue", colorScheme: patch.colorScheme ?? "system", updatedAt: .now)
    }
}

@MainActor
@Suite struct AppearanceSyncTests {
    private let accountA = UUID()
    private let accountB = UUID()

    private func makeDefaults(accent: String? = nil, scheme: String? = nil, owner: UUID? = nil, pending: UUID? = nil, custom: String? = nil) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "test.appearance.\(UUID().uuidString)")!
        if let accent { defaults.set(accent, forKey: AppearanceStorageKeys.accent) }
        if let scheme { defaults.set(scheme, forKey: AppearanceStorageKeys.scheme) }
        if let custom { defaults.set(custom, forKey: AppearanceStorageKeys.customHex) }
        if let owner { defaults.set(owner.uuidString, forKey: AppearanceStorageKeys.owner) }
        if let pending { defaults.set(pending.uuidString, forKey: AppearanceStorageKeys.pending) }
        return defaults
    }

    private func sync(_ defaults: UserDefaults) -> AppearanceSync {
        AppearanceSync(defaults: defaults, debounce: .milliseconds(10), retryDelay: .seconds(3600))
    }

    @Test func accountValuesReplaceTheCache() async {
        let defaults = makeDefaults(accent: "teal", scheme: "light", owner: accountA)
        let sync = sync(defaults)
        let service = FakeService()
        await sync.connect(accountId: accountA, service: service, serverPreferences: Preferences(accent: "orange", colorScheme: "dark", updatedAt: .now), canWrite: true)
        #expect(defaults.string(forKey: AppearanceStorageKeys.accent) == "orange")
        #expect(defaults.string(forKey: AppearanceStorageKeys.scheme) == "dark")
        #expect(sync.status == .synced)
        #expect(service.sent.isEmpty)
    }

    @Test func customHexIsCached() async {
        let defaults = makeDefaults()
        let sync = sync(defaults)
        await sync.connect(accountId: accountA, service: FakeService(), serverPreferences: Preferences(accent: "custom", accentCustomHex: "#AB12CD", colorScheme: "system", updatedAt: .now), canWrite: true)
        #expect(defaults.string(forKey: AppearanceStorageKeys.accent) == "custom")
        #expect(defaults.string(forKey: AppearanceStorageKeys.customHex) == "#AB12CD")
    }

    @Test func unsentLocalChangeWinsAndIsPushed() async {
        let defaults = makeDefaults(accent: "pink", scheme: "dark", owner: accountA, pending: accountA)
        let sync = sync(defaults)
        let service = FakeService()
        await sync.connect(accountId: accountA, service: service, serverPreferences: Preferences(accent: "orange", updatedAt: .now), canWrite: true)
        await sync.waitUntilIdle()
        #expect(service.sent == [PreferencesPatch(accent: "pink", colorScheme: "dark")])
        #expect(defaults.string(forKey: AppearanceStorageKeys.accent) == "pink")
        #expect(!sync.hasPending(for: accountA))
        #expect(sync.status == .synced)
    }

    @Test func pendingOfAnotherAccountDoesNotLeak() async {
        let defaults = makeDefaults(accent: "pink", owner: accountA, pending: accountA)
        let sync = sync(defaults)
        let service = FakeService()
        await sync.connect(accountId: accountB, service: service, serverPreferences: Preferences(accent: "green", updatedAt: .now), canWrite: true)
        await sync.waitUntilIdle()
        #expect(service.sent.isEmpty)
        #expect(defaults.string(forKey: AppearanceStorageKeys.accent) == "green")
    }

    @Test func firstMigrationUploadsLegacyChoiceOnce() async {
        let defaults = makeDefaults(accent: "violet", scheme: "dark") // A6d cache without owner
        let sync = sync(defaults)
        let service = FakeService()
        await sync.connect(accountId: accountA, service: service, serverPreferences: Preferences(), canWrite: true)
        await sync.waitUntilIdle()
        #expect(service.sent == [PreferencesPatch(accent: "violet", colorScheme: "dark")])
        #expect(defaults.string(forKey: AppearanceStorageKeys.owner) == accountA.uuidString)
        // Second launch: the account is set now, the server value wins and nothing is sent again.
        await sync.connect(accountId: accountA, service: service, serverPreferences: Preferences(accent: "violet", colorScheme: "dark", updatedAt: .now), canWrite: true)
        #expect(service.sent.count == 1)
    }

    @Test func migrationSkippedForForeignCacheOrDefaults() async {
        let foreign = makeDefaults(accent: "violet", owner: accountA)
        let service = FakeService()
        await sync(foreign).connect(accountId: accountB, service: service, serverPreferences: Preferences(), canWrite: true)
        #expect(service.sent.isEmpty)
        #expect(foreign.string(forKey: AppearanceStorageKeys.accent) == "blue")

        let defaultsOnly = makeDefaults()
        await sync(defaultsOnly).connect(accountId: accountB, service: service, serverPreferences: Preferences(), canWrite: true)
        #expect(service.sent.isEmpty)
    }

    @Test func olderServerStaysLocal() async {
        let defaults = makeDefaults(accent: "violet", owner: accountA)
        let sync = sync(defaults)
        let service = FakeService()
        await sync.connect(accountId: accountA, service: service, serverPreferences: nil, canWrite: true)
        defaults.set("green", forKey: AppearanceStorageKeys.accent)
        sync.localChanged()
        await sync.waitUntilIdle()
        #expect(service.sent.isEmpty && sync.status == .localOnly)
    }

    @Test func recoverySessionOnlyApplies() async {
        let defaults = makeDefaults(accent: "violet")
        let sync = sync(defaults)
        let service = FakeService()
        await sync.connect(accountId: accountA, service: service, serverPreferences: Preferences(accent: "teal", updatedAt: .now), canWrite: false)
        #expect(defaults.string(forKey: AppearanceStorageKeys.accent) == "teal")
        defaults.set("green", forKey: AppearanceStorageKeys.accent)
        sync.localChanged()
        await sync.waitUntilIdle()
        #expect(service.sent.isEmpty && !sync.hasPending(for: accountA))
    }

    @Test func unknownFutureAccentShowsBlueAndIsNotWrittenBack() async {
        let defaults = makeDefaults(accent: "teal", owner: accountA)
        let sync = sync(defaults)
        let service = FakeService()
        await sync.connect(accountId: accountA, service: service, serverPreferences: Preferences(accent: "magenta", colorScheme: "twilight", updatedAt: .now), canWrite: true)
        await sync.waitUntilIdle()
        #expect(defaults.string(forKey: AppearanceStorageKeys.accent) == "blue")
        #expect(defaults.string(forKey: AppearanceStorageKeys.scheme) == "system")
        #expect(service.sent.isEmpty)
    }

    @Test func changeIsDebouncedAndOnlyTheNewestStateIsSent() async {
        let defaults = makeDefaults(owner: accountA)
        let sync = AppearanceSync(defaults: defaults, debounce: .milliseconds(80), retryDelay: .seconds(3600))
        let service = FakeService()
        await sync.connect(accountId: accountA, service: service, serverPreferences: Preferences(updatedAt: .now), canWrite: true)
        for accent in ["teal", "green", "orange"] {
            defaults.set(accent, forKey: AppearanceStorageKeys.accent)
            sync.localChanged()
        }
        #expect(sync.status == .pending)
        await sync.waitUntilIdle()
        #expect(service.sent == [PreferencesPatch(accent: "orange", colorScheme: "system")])
        #expect(sync.status == .synced)
    }

    @Test func customColourSendsHexOthersDoNot() {
        #expect(LocalAppearance(accent: "custom", customHex: "#ab12cd", scheme: "light").patch == PreferencesPatch(accent: "custom", colorScheme: "light", customHex: .set("#AB12CD")))
        #expect(LocalAppearance(accent: "custom", customHex: "oops", scheme: "light").patch == PreferencesPatch(accent: "blue", colorScheme: "light"))
        #expect(LocalAppearance(accent: "graphite", customHex: "#AB12CD", scheme: "dark").patch == PreferencesPatch(accent: "graphite", colorScheme: "dark"))
    }

    @Test func offlineKeepsMarkAndRetriesLater() async {
        let defaults = makeDefaults(owner: accountA)
        let sync = sync(defaults)
        let service = FakeService()
        await sync.connect(accountId: accountA, service: service, serverPreferences: Preferences(updatedAt: .now), canWrite: true)
        service.failNext(.network(.notConnectedToInternet))
        defaults.set("pink", forKey: AppearanceStorageKeys.accent)
        sync.localChanged()
        await sync.waitUntilIdle()
        #expect(sync.status == .pending && sync.hasPending(for: accountA))
        #expect(defaults.string(forKey: AppearanceStorageKeys.accent) == "pink") // offline keeps the local value
        await sync.retryNow()
        #expect(sync.status == .synced && !sync.hasPending(for: accountA))
        #expect(service.sent.count == 2)
    }

    @Test func serverErrorsKeepTheMarkBadRequestDropsIt() async {
        let defaults = makeDefaults(owner: accountA)
        let sync = sync(defaults)
        let service = FakeService()
        await sync.connect(accountId: accountA, service: service, serverPreferences: Preferences(updatedAt: .now), canWrite: true)
        service.failNext(.api(status: 503, code: "http_503", message: "x"))
        defaults.set("pink", forKey: AppearanceStorageKeys.accent)
        sync.localChanged()
        await sync.waitUntilIdle()
        if case .failed = sync.status {} else { Issue.record("expected failed") }
        #expect(sync.hasPending(for: accountA))

        service.failNext(.api(status: 400, code: "bad_request", message: "x"))
        await sync.retryNow()
        if case .failed = sync.status {} else { Issue.record("expected failed") }
        #expect(!sync.hasPending(for: accountA))
    }

    @Test func widgetSnapshotCarriesAccentAdditively() throws {
        var snapshot = WidgetSnapshot.empty
        #expect(snapshot.accentHex == nil)
        snapshot = WidgetSnapshot(isRunning: false, kind: .work, startedAt: nil, todaySeconds: 0, day: "2026-10-16", timeZone: "Europe/Berlin", updatedAt: .now, accentHex: "#f97316", colorScheme: "dark")
        #expect(snapshot.accentHex == "#F97316" && snapshot.colorScheme == "dark")
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
        // Snapshots written by older builds decode without the new keys.
        let old = #"{"isRunning":false,"kind":"work","todaySeconds":0,"day":"2026-10-16","timeZone":"UTC","updatedAt":0}"#
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8)).accentHex == nil)
        // Garbage never reaches the widgets.
        #expect(WidgetSnapshot(isRunning: false, kind: .work, startedAt: nil, todaySeconds: 0, day: "", timeZone: "UTC", updatedAt: .now, accentHex: "javascript:1", colorScheme: "x").accentHex == nil)
    }
}
