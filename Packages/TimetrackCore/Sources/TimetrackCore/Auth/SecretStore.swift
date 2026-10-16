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
}
