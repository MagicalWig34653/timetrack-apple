import Foundation

// AUD3-A (contract 0.36.0): passkeys, recovery methods and linked identities of the account.

public struct Passkey: Decodable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let lastUsedAt: Date?

    public init(id: UUID, name: String, createdAt: Date, lastUsedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct ExternalIdentity: Decodable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let providerName: String
    /// The provider's e-mail address as a hint only; never a linking basis.
    public let emailHint: String?
    public let linkedAt: Date
    public let lastUsedAt: Date?

    public init(id: UUID, providerName: String, emailHint: String? = nil, linkedAt: Date, lastUsedAt: Date? = nil) {
        self.id = id
        self.providerName = providerName
        self.emailHint = emailHint
        self.linkedAt = linkedAt
        self.lastUsedAt = lastUsedAt
    }
}

/// `GET /me/recovery`.
public struct RecoveryStatus: Decodable, Sendable, Equatable {
    public struct Codes: Decodable, Sendable, Equatable {
        public let active: Bool
        public let remaining: Int?
    }

    public struct FallbackPassword: Decodable, Sendable, Equatable { public let active: Bool }

    public struct Email: Decodable, Sendable, Equatable {
        /// False when the server cannot send mail.
        public var available: Bool
        public let active: Bool
        /// Account e-mail confirmed; nil from servers older than 0.36.0.
        public let verified: Bool?
        /// The address codes go to (the account e-mail, ADR-0032).
        public let accountEmail: String?

        public init(available: Bool, active: Bool, verified: Bool? = nil, accountEmail: String? = nil) {
            self.available = available
            self.active = active
            self.verified = verified
            self.accountEmail = accountEmail
        }
    }

    public let recoveryCodes: Codes
    public let fallbackPassword: FallbackPassword
    public var email: Email

    public init(codesActive: Bool, remaining: Int? = nil, passwordActive: Bool = false, email: Email) {
        recoveryCodes = Codes(active: codesActive, remaining: remaining)
        fallbackPassword = FallbackPassword(active: passwordActive)
        self.email = email
    }

    /// True when at least one way back into the account exists besides a passkey.
    public var hasAnyMethod: Bool { recoveryCodes.active || fallbackPassword.active || email.active }
}

/// What the E-Mail-Wiederherstellung card shows (same order of checks as the web app).
public enum EmailRecoveryState: Sendable, Equatable {
    case unavailable
    case noAccountEmail
    case active(email: String)
    /// Account e-mail exists but is not confirmed yet: confirm it in the profile first.
    case unconfirmed(email: String)
    case canEnable(email: String)

    public init(_ email: RecoveryStatus.Email) {
        if !email.available { self = .unavailable; return }
        guard let address = email.accountEmail, !address.isEmpty else { self = .noAccountEmail; return }
        if email.active { self = .active(email: address); return }
        self = email.verified == false ? .unconfirmed(email: address) : .canEnable(email: address)
    }
}

/// Answer of `PUT /me/recovery/email`.
public enum EmailRecoveryStart: Sendable, Equatable { case active, codeSent }

public enum RecoveryValidation {
    public static let passwordMinimum = 12
    public static let passwordMaximum = 256

    public enum PasswordProblem: Sendable, Equatable { case tooShort, tooLong, mismatch }

    public static func passwordProblem(_ password: String, repeated: String) -> PasswordProblem? {
        if password.count < passwordMinimum { return .tooShort }
        if password.count > passwordMaximum { return .tooLong }
        if password != repeated { return .mismatch }
        return nil
    }
}
