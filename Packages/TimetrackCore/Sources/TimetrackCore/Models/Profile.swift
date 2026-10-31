import Foundation

// AUD3-A (contract 0.13.0): `GET/PATCH /me/profile` and the e-mail change with a confirmation code.

public struct Profile: Decodable, Sendable, Equatable {
    public enum Onboarding: String, Decodable, Sendable { case pending, completed, skipped, unknown }

    public let handle: String
    public let displayName: String
    public let email: String?
    public let emailVerified: Bool
    /// An address waiting for its code.
    public let pendingEmail: String?
    /// False when the server has no SMTP: the address stays optional and unconfirmed.
    public let mailAvailable: Bool
    public let onboarding: Onboarding

    private enum CodingKeys: String, CodingKey { case handle, displayName, email, emailVerified, pendingEmail, mailAvailable, onboarding }
    private struct OnboardingBody: Decodable { let state: String? }

    public init(handle: String, displayName: String, email: String? = nil, emailVerified: Bool = false, pendingEmail: String? = nil,
                mailAvailable: Bool = true, onboarding: Onboarding = .completed) {
        self.handle = handle
        self.displayName = displayName
        self.email = email
        self.emailVerified = emailVerified
        self.pendingEmail = pendingEmail
        self.mailAvailable = mailAvailable
        self.onboarding = onboarding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = try c.decode(String.self, forKey: .handle)
        displayName = try c.decode(String.self, forKey: .displayName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        emailVerified = try c.decode(Bool.self, forKey: .emailVerified)
        pendingEmail = try c.decodeIfPresent(String.self, forKey: .pendingEmail)
        mailAvailable = try c.decode(Bool.self, forKey: .mailAvailable)
        let state = (try? c.decodeIfPresent(OnboardingBody.self, forKey: .onboarding))??.state
        onboarding = state.flatMap(Onboarding.init(rawValue:)) ?? .unknown
    }
}

/// Client-side checks that mirror the web app's profile page (the server stays the authority).
public enum ProfileValidation {
    public static let displayNameLimit = 80

    /// The trimmed name when it has 1 to 80 characters.
    public static func displayName(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...displayNameLimit).contains(trimmed.count) ? trimmed : nil
    }

    /// The trimmed address when it looks like `a@b.c` (same loose rule as the web app).
    public static func email(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[0].contains(where: \.isWhitespace),
              !parts[1].contains(where: \.isWhitespace),
              let dot = parts[1].lastIndex(of: "."), dot != parts[1].startIndex, parts[1].index(after: dot) != parts[1].endIndex else { return nil }
        return trimmed
    }
}
