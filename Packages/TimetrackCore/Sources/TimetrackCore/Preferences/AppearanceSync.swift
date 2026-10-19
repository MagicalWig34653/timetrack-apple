import Foundation
import Observation

/// UserDefaults keys of the appearance cache. The three value keys keep their A6d names; the two marker keys are new.
public enum AppearanceStorageKeys {
    public static let accent = "appearance.accent"
    public static let customHex = "appearance.customHex"
    public static let scheme = "appearance.scheme"
    /// "Leuchteffekt": `off|subtle|medium|strong` (N1b).
    public static let glow = "appearance.glow"
    /// Account id the cached values belong to (so a choice never flows into somebody else's account).
    public static let owner = "appearance.cacheOwner"
    /// Account id with an unsent local change.
    public static let pending = "appearance.pendingAccount"
}

/// The appearance choice stored on this device (the instant cache).
public struct LocalAppearance: Sendable, Equatable {
    public var accent: String
    public var customHex: String
    public var scheme: String
    public var glow: String

    public static let defaultCustomHex = "#2563EB"
    public static let defaults = LocalAppearance(accent: Preferences.defaultAccent, customHex: defaultCustomHex, scheme: Preferences.defaultColorScheme)

    public init(accent: String, customHex: String, scheme: String, glow: String = Preferences.defaultGlow) {
        self.accent = accent
        self.customHex = customHex
        self.scheme = scheme
        self.glow = glow
    }

    /// True when the visible choice differs from the defaults (the custom hex only matters for `custom`).
    public var differsFromDefaults: Bool {
        accent != Preferences.defaultAccent || scheme != Preferences.defaultColorScheme || glow != Preferences.defaultGlow
    }

    /// Patch for the contract: always `accent`, `colorScheme` and `glow`, the hex only with `custom` (a malformed hex degrades to `blue`).
    public var patch: PreferencesPatch {
        let scheme = ColorSchemePreference(rawValue: scheme)?.rawValue ?? Preferences.defaultColorScheme
        let glow = GlowPreference(rawValue: glow)?.rawValue ?? Preferences.defaultGlow
        if accent == AccentPreset.custom.rawValue, let hex = Preferences.normalizedHex(customHex) {
            return PreferencesPatch(accent: AccentPreset.custom.rawValue, colorScheme: scheme, glow: glow, customHex: .set(hex))
        }
        let preset = AccentPreset(rawValue: accent).flatMap { $0 == .custom ? nil : $0 } ?? .blue
        return PreferencesPatch(accent: preset.rawValue, colorScheme: scheme, glow: glow)
    }

    /// Patches to try, in order, when the server answers 400 to `patch` (servers before contract v0.21.0 reject the six newest
    /// ids, servers before v0.15.0 also reject `glow` and the v0.15.0 ids). Like the PWA, a rejected preset is sent as
    /// `custom` plus its hex (the colour survives, the name does not); `glow` stays local when even that is rejected.
    public var fallbackPatches: [PreferencesPatch] {
        let scheme = ColorSchemePreference(rawValue: scheme)?.rawValue ?? Preferences.defaultColorScheme
        let glow = GlowPreference(rawValue: glow)?.rawValue ?? Preferences.defaultGlow
        let preset = AccentPreset(rawValue: accent) ?? .blue
        var candidates: [PreferencesPatch] = []
        func hexed() -> PreferencesPatch? {
            guard preset != .custom, !preset.isLegacy || preset.needsV021, let hex = preset.nativeHex.map(AccentPresetHex.string) else { return nil }
            return PreferencesPatch(accent: AccentPreset.custom.rawValue, colorScheme: scheme, glow: glow, customHex: .set(hex))
        }
        if let withGlow = hexed() {
            if preset.needsV021 { candidates.append(withGlow) }
            var plain = withGlow
            plain.glow = nil
            candidates.append(plain)
        } else {
            var plain = patch
            plain.glow = nil
            candidates.append(plain)
        }
        let original = patch
        var result: [PreferencesPatch] = []
        for candidate in candidates where candidate != original && !result.contains(candidate) { result.append(candidate) }
        return result
    }
}

/// `#RRGGBB` text of a hex number (shared by the preset table and the fallback patches).
public enum AccentPresetHex {
    public static func string(_ hex: UInt32) -> String { String(format: "#%06X", hex) }
}

/// Keeps the local appearance cache and the account's preferences in step (P2 handoff, "Abgleich").
///
/// - The cache in `UserDefaults` is applied instantly by the views (`@AppStorage`); this class only reconciles it.
/// - A local change is written to the cache first, marked as pending for the account and sent debounced with `PATCH`;
///   only the newest state is sent, never two requests in parallel. Network errors, 5xx, 401, 403 and 429 keep the mark
///   (retried later), a 400 discards it.
/// - After sign-in / session restore, `connect` applies the account values unless an unsent change of the same account waits.
@MainActor
@Observable
public final class AppearanceSync {
    public enum Status: Equatable, Sendable {
        /// No account, an older server without `account.preferences`, or a restricted session: only this device.
        case localOnly
        case synced
        /// A request is running.
        case syncing
        /// Waiting for a request (debounce, offline, retry).
        case pending
        /// The server rejected the value or the request keeps failing for a non-network reason.
        case failed(TimetrackError)
    }

    public private(set) var status: Status = .localOnly
    /// The current local choice (also what the widgets are told about). Refreshed by `localChanged()` and `connect`.
    public private(set) var local: LocalAppearance

    private let defaults: UserDefaults
    private let debounce: Duration
    private let retryDelay: Duration
    private var accountId: UUID?
    private var service: (any PreferencesService)?
    private var canWrite = false
    private var pushTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var pushing = false

    public init(defaults: UserDefaults = .standard, debounce: Duration = .milliseconds(700), retryDelay: Duration = .seconds(30)) {
        self.defaults = defaults
        self.debounce = debounce
        self.retryDelay = retryDelay
        local = Self.read(defaults)
    }

    // MARK: - Cache

    private static func read(_ defaults: UserDefaults) -> LocalAppearance {
        LocalAppearance(
            accent: defaults.string(forKey: AppearanceStorageKeys.accent) ?? LocalAppearance.defaults.accent,
            customHex: defaults.string(forKey: AppearanceStorageKeys.customHex) ?? LocalAppearance.defaultCustomHex,
            scheme: defaults.string(forKey: AppearanceStorageKeys.scheme) ?? LocalAppearance.defaults.scheme,
            glow: defaults.string(forKey: AppearanceStorageKeys.glow) ?? Preferences.defaultGlow
        )
    }

    private func write(_ value: LocalAppearance) {
        defaults.set(value.accent, forKey: AppearanceStorageKeys.accent)
        defaults.set(value.customHex, forKey: AppearanceStorageKeys.customHex)
        defaults.set(value.scheme, forKey: AppearanceStorageKeys.scheme)
        defaults.set(value.glow, forKey: AppearanceStorageKeys.glow)
        local = value
    }

    private var owner: UUID? { defaults.string(forKey: AppearanceStorageKeys.owner).flatMap(UUID.init(uuidString:)) }
    private func setOwner(_ id: UUID?) { defaults.set(id?.uuidString, forKey: AppearanceStorageKeys.owner) }

    /// True when an unsent change of `account` waits.
    public func hasPending(for account: UUID) -> Bool { defaults.string(forKey: AppearanceStorageKeys.pending) == account.uuidString }
    private func setPending(_ account: UUID?) { defaults.set(account?.uuidString, forKey: AppearanceStorageKeys.pending) }

    /// Cache values for a server answer: unknown future ids show as the defaults; the custom hex is only taken when valid.
    static func cacheValue(for prefs: Preferences, keeping current: LocalAppearance) -> LocalAppearance {
        var value = current
        value.accent = prefs.accentPreset.rawValue
        value.scheme = prefs.scheme.rawValue
        if prefs.hasGlow { value.glow = prefs.glowLevel.rawValue } // an older server stays silent: keep the local choice
        if prefs.accentPreset == .custom, let hex = prefs.customHex {
            value.customHex = hex
        } else if prefs.accentPreset == .custom {
            value.accent = AccentPreset.blue.rawValue // custom without a valid hex cannot be shown
        }
        return value
    }

    // MARK: - Session

    /// Reconciles after a session was loaded. `serverPreferences == nil` means an older server: nothing is sent.
    public func connect(accountId: UUID, service: (any PreferencesService)?, serverPreferences: Preferences?, canWrite: Bool) async {
        cancelTasks()
        self.accountId = accountId
        self.canWrite = canWrite
        local = Self.read(defaults)
        guard let serverPreferences, let service else {
            self.service = nil
            status = .localOnly
            return
        }
        self.service = service

        if hasPending(for: accountId) {
            // 2. An unsent local change of this account wins and is pushed.
            status = .pending
            if canWrite { startPush() } else { status = .localOnly }
            return
        }
        setPending(nil) // a mark of another account is obsolete: the account's own values replace the cache
        let cacheBelongsToOther = owner != nil && owner != accountId
        if serverPreferences.isUnset, !cacheBelongsToOther, local.differsFromDefaults, canWrite {
            // 6. First migration: the account never chose; upload the old local choice once.
            setOwner(accountId)
            setPending(accountId)
            status = .pending
            startPush()
            return
        }
        write(Self.cacheValue(for: serverPreferences, keeping: local))
        setOwner(accountId)
        status = canWrite ? .synced : .localOnly
    }

    /// Starts the push without blocking sign-in (the page shows the status meanwhile).
    private func startPush() {
        pushTask = Task { await self.push() }
    }

    /// Waits for a push started by `connect` or by the debounce (used by tests).
    public func waitUntilIdle() async { await pushTask?.value }

    /// Sign-out or reset: the cache stays for the sign-in screen, nothing is sent any more.
    public func disconnect() {
        cancelTasks()
        accountId = nil
        service = nil
        canWrite = false
        status = .localOnly
    }

    /// Re-reads the account values when the Darstellung page opens (only when nothing waits).
    public func refreshFromServer() async {
        guard let accountId, let service, canWrite, !hasPending(for: accountId), !pushing else { return }
        guard let prefs = try? await service.getPreferences(), !hasPending(for: accountId), self.accountId == accountId else { return }
        write(Self.cacheValue(for: prefs, keeping: Self.read(defaults)))
        setOwner(accountId)
        status = .synced
    }

    // MARK: - Local changes

    /// Called after the views changed the cache keys (accent, custom colour, scheme).
    public func localChanged() {
        let value = Self.read(defaults)
        guard value != local else { return }
        local = value
        guard let accountId, service != nil, canWrite else { return }
        setOwner(accountId)
        setPending(accountId)
        if pushing { return } // the running push loop notices the change and sends the newest state next
        status = .pending
        retryTask?.cancel()
        pushTask?.cancel()
        pushTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.push()
        }
    }

    /// Sends the newest local state; loops while the user keeps changing it. Single flight.
    public func push() async {
        guard let accountId, let service, canWrite, hasPending(for: accountId), !pushing else { return }
        pushing = true
        defer { pushing = false }
        while hasPending(for: accountId) {
            let sent = Self.read(defaults)
            status = .syncing
            do {
                _ = try await Self.send(sent, with: service)
                guard self.accountId == accountId else { return }
                if Self.read(defaults) != sent { continue } // changed meanwhile: send the newest state next
                setPending(nil)
                status = .synced
            } catch let error as TimetrackError {
                guard self.accountId == accountId else { return }
                if error.status == 400 {
                    setPending(nil) // the server will never accept this value
                    status = .failed(error)
                } else {
                    status = error.isNetworkError ? .pending : .failed(error)
                    scheduleRetry()
                }
                return
            } catch {
                status = .pending
                scheduleRetry()
                return
            }
        }
    }

    /// Sends the full patch; on 400 retries with the compatibility patches for older servers (see `fallbackPatches`).
    static func send(_ value: LocalAppearance, with service: any PreferencesService) async throws -> Preferences {
        do {
            return try await service.updatePreferences(value.patch)
        } catch let error as TimetrackError where error.status == 400 {
            for fallback in value.fallbackPatches {
                do { return try await service.updatePreferences(fallback) } catch let next as TimetrackError where next.status == 400 { continue }
            }
            throw error
        }
    }

    /// Retry hook for app activation or the page: sends a waiting change now.
    public func retryNow() async {
        retryTask?.cancel()
        await push()
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [retryDelay] in
            try? await Task.sleep(for: retryDelay)
            guard !Task.isCancelled else { return }
            await self.push()
        }
    }

    private func cancelTasks() {
        pushTask?.cancel()
        retryTask?.cancel()
        pushTask = nil
        retryTask = nil
    }
}
