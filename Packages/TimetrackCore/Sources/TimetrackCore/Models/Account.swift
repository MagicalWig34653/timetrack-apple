import Foundation

public struct Account: Codable, Sendable, Hashable, Identifiable {
    public enum Role: String, Codable, Sendable { case admin, member }
    public let id: UUID
    public let handle: String
    public let displayName: String
    public let role: Role

    public init(id: UUID, handle: String, displayName: String, role: Role) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.role = role
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
