import Foundation

public struct Account: Codable, Sendable, Hashable, Identifiable {
    public enum Role: String, Codable, Sendable { case admin, member }
    public let id: UUID
    public let handle: String
    public let displayName: String
    public let role: Role
    /// Account-level appearance (`account.preferences` in the session response); nil from servers older than contract v0.14.0.
    public let preferences: Preferences?

    public init(id: UUID, handle: String, displayName: String, role: Role, preferences: Preferences? = nil) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.role = role
        self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey { case id, handle, displayName, role, preferences }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        handle = try c.decode(String.self, forKey: .handle)
        displayName = try c.decode(String.self, forKey: .displayName)
        role = try c.decode(Role.self, forKey: .role)
        // Appearance is cosmetic: a malformed block must never break signing in.
        preferences = (try? c.decodeIfPresent(Preferences.self, forKey: .preferences)) ?? nil
    }
}

/// `GET /auth/session` and every login response. `recovery == true` is a restricted session (ADR-0003).
public struct Session: Codable, Sendable, Hashable {
    public let account: Account
    public let csrfToken: String
    public let recovery: Bool
    public let expiresAt: Date?

    public init(account: Account, csrfToken: String, recovery: Bool, expiresAt: Date? = nil) {
        self.account = account
        self.csrfToken = csrfToken
        self.recovery = recovery
        self.expiresAt = expiresAt
    }
}

public enum RecoveryMethod: String, Codable, Sendable, CaseIterable {
    case email
    case recoveryCode = "recovery-code"
    case fallbackPassword = "fallback-password"
}

public struct RecoveryStart: Codable, Sendable, Hashable {
    public let recoveryId: String
}

/// W3C options as sent by the backend: `{ challengeId, publicKey }` with `publicKey` kept opaque.
public struct WebAuthnOptions: Codable, Sendable, Hashable {
    public let challengeId: String
    public let publicKey: JSONValue
}
