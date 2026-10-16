import Foundation

/// Platform passkey operations. The server sends W3C `PublicKeyCredential*OptionsJSON`; the result is the
/// matching `*ResponseJSON` (base64url fields) that the backend verifies unchanged.
///
/// Missing for a real run (see docs/handoffs/A1.md): Apple team ID, bundle IDs, the `webcredentials:<host>` Associated
/// Domains entitlement and an `apple-app-site-association` file served by the backend (planned backend work A2).
public protocol PasskeyAuthenticator: Sendable {
    func register(options: WebAuthnOptions) async throws -> JSONValue
    func authenticate(options: WebAuthnOptions) async throws -> JSONValue
}

/// Used when no authenticator is wired (tests, previews, watchOS before relay exists).
public struct UnavailablePasskeyAuthenticator: PasskeyAuthenticator {
    public init() {}
    public func register(options: WebAuthnOptions) async throws -> JSONValue { throw TimetrackError.passkey("unavailable") }
    public func authenticate(options: WebAuthnOptions) async throws -> JSONValue { throw TimetrackError.passkey("unavailable") }
}

/// base64url helpers (no padding), the encoding of all WebAuthn JSON binary fields.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
