import Foundation
import Security

/// Small secret storage (server URL and session cookie). The apps use the Keychain; tests use memory.
public protocol SecretStore: Sendable {
    func read(_ key: String) -> String?
    func write(_ value: String, for key: String)
    func delete(_ key: String)
}

public enum SecretKey {
    public static let serverURL = "server-url"
    public static let sessionCookie = "session-cookie"
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func read(_ key: String) -> String? { lock.withLock { values[key] } }
    public func write(_ value: String, for key: String) { lock.withLock { values[key] = value } }
    public func delete(_ key: String) { lock.withLock { values[key] = nil } }
}

/// HG1: `SecItemCopyMatching` is a synchronous XPC round trip to securityd (seen on the main thread in a runloop hang report).
/// This wrapper answers reads of the listed keys from memory once they were read or written, and can `prefetch` them on a
/// background thread, so main-actor code (stores, `body`) never waits for the Keychain. Only for keys that this process alone
/// writes (not the session keys that the widget, intents and the watch handoff also touch). Other keys pass straight through.
public final class CachedSecretStore: SecretStore, @unchecked Sendable {
    private let base: SecretStore
    private let cachedKeys: Set<String>
    private let lock = NSLock()
    /// `.some(nil)` caches "no such item" as well.
    private var cache: [String: String?] = [:]

    public init(_ base: SecretStore, cachedKeys: Set<String>) {
        self.base = base
        self.cachedKeys = cachedKeys
    }

    public func read(_ key: String) -> String? {
        guard cachedKeys.contains(key) else { return base.read(key) }
        if let hit = lock.withLock({ cache[key] }) { return hit }
        let value = base.read(key) // outside the lock: the query may block
        return lock.withLock {
            if let existing = cache[key] { return existing } // a write or another read won the race
            cache[key] = .some(value)
            return value
        }
    }

    public func write(_ value: String, for key: String) {
        base.write(value, for: key)
        if cachedKeys.contains(key) { lock.withLock { cache[key] = .some(value) } }
    }

    public func delete(_ key: String) {
        base.delete(key)
        if cachedKeys.contains(key) { lock.withLock { cache[key] = .some(nil) } }
    }

    /// Reads the cached keys from the base store; call off the main thread.
    public func prefetch() {
        for key in cachedKeys.sorted() { _ = read(key) }
    }
}

/// Generic-password Keychain items. Values are never logged.
public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "app.timetrack.client") { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        #if !os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    public func read(_ key: String) -> String? {
        var request = query(key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = query(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }

    /// Re-creates the stored secrets without an explicit access group, so they land in the app's default group (the first
    /// `keychain-access-groups` entry, which the iOS widget extension shares). Items written by builds that had no such entitlement
    /// sit in the application-identifier group, which the extension cannot read. Idempotent; without the entitlement it is a no-op move.
    public func migrateToDefaultAccessGroup() {
        for key in [SecretKey.serverURL, SecretKey.sessionCookie] {
            guard let value = read(key) else { continue }
            delete(key)
            write(value, for: key)
            if read(key) == nil { write(value, for: key) }
        }
    }
}
