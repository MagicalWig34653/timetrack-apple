#if canImport(AuthenticationServices) && (os(macOS) || os(iOS))
import AuthenticationServices
import Foundation

/// AuthenticationServices implementation. It is complete on the code side but cannot run end to end before the app
/// has the `webcredentials:<host>` Associated Domains entitlement and the server serves an AASA file naming the app ID.
@MainActor
public final class PlatformPasskeyAuthenticator: NSObject, PasskeyAuthenticator, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private let anchorProvider: @MainActor () -> ASPresentationAnchor

    public init(anchorProvider: @escaping @MainActor () -> ASPresentationAnchor) {
        self.anchorProvider = anchorProvider
    }

    public func register(options: WebAuthnOptions) async throws -> JSONValue {
        let authorization = try await run(try Self.registrationRequest(options))
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw TimetrackError.passkey("unexpected credential")
        }
        return Self.registrationJSON(credential)
    }

    public func authenticate(options: WebAuthnOptions) async throws -> JSONValue {
        let authorization = try await run(try Self.assertionRequest(options))
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw TimetrackError.passkey("unexpected credential")
        }
        return Self.assertionJSON(credential)
    }

    // MARK: - Requests (W3C JSON -> AuthenticationServices)

    private static func registrationRequest(_ options: WebAuthnOptions) throws -> ASAuthorizationRequest {
        let key = options.publicKey
        guard let rpId = key["rp"]?["id"]?.stringValue,
              let challenge = key["challenge"]?.stringValue.flatMap(Base64URL.decode),
              let user = key["user"],
              let name = user["name"]?.stringValue,
              let userId = user["id"]?.stringValue.flatMap(Base64URL.decode) else { throw TimetrackError.passkey("invalid options") }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        return provider.createCredentialRegistrationRequest(challenge: challenge, name: name, userID: userId)
    }

    private static func assertionRequest(_ options: WebAuthnOptions) throws -> ASAuthorizationRequest {
        let key = options.publicKey
        guard let challenge = key["challenge"]?.stringValue.flatMap(Base64URL.decode) else { throw TimetrackError.passkey("invalid options") }
        let rpId = key["rpId"]?.stringValue ?? ""
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        let allowed = key["allowCredentials"]?.arrayValue?.compactMap { $0["id"]?.stringValue.flatMap(Base64URL.decode) } ?? []
        if !allowed.isEmpty {
            request.allowedCredentials = allowed.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        }
        return request
    }

    // MARK: - Responses (AuthenticationServices -> W3C JSON)

    private static func registrationJSON(_ credential: ASAuthorizationPlatformPublicKeyCredentialRegistration) -> JSONValue {
        let id = Base64URL.encode(credential.credentialID)
        return .object([
            "id": .string(id), "rawId": .string(id), "type": .string("public-key"),
            "authenticatorAttachment": .string("platform"),
            "response": .object([
                "clientDataJSON": .string(Base64URL.encode(credential.rawClientDataJSON)),
                "attestationObject": .string(Base64URL.encode(credential.rawAttestationObject ?? Data())),
            ]),
            "clientExtensionResults": .object([:]),
        ])
    }

    private static func assertionJSON(_ credential: ASAuthorizationPlatformPublicKeyCredentialAssertion) -> JSONValue {
        let id = Base64URL.encode(credential.credentialID)
        return .object([
            "id": .string(id), "rawId": .string(id), "type": .string("public-key"),
            "authenticatorAttachment": .string("platform"),
            "response": .object([
                "clientDataJSON": .string(Base64URL.encode(credential.rawClientDataJSON)),
                "authenticatorData": .string(Base64URL.encode(credential.rawAuthenticatorData)),
                "signature": .string(Base64URL.encode(credential.signature)),
                "userHandle": .string(Base64URL.encode(credential.userID)),
            ]),
            "clientExtensionResults": .object([:]),
        ])
    }

    // MARK: - Controller plumbing

    private func run(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: TimetrackError.passkey((error as? ASAuthorizationError).map { "code \($0.code.rawValue)" } ?? "failed"))
        continuation = nil
    }

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchorProvider() }
}

#endif
