import Foundation

/// Pure state machine for the session of a client that must stay usable on its own (the watch app, A12).
///
/// Credentials found locally make the client usable at once (`active(.unverified)`); the server check runs in the
/// background and either confirms (`verified`), cannot be reached (`offline`, still usable: actions are queued) or
/// rejects the session (`signedOut(.expired)`, the only state that asks the user to sign in again).
public struct SessionLifecycle: Equatable, Sendable {
    public enum Verification: Equatable, Sendable {
        /// Credentials exist locally; the server has not answered yet.
        case unverified
        case verified
        /// The last check failed because the server could not be reached. Credentials are kept.
        case offline
    }

    public enum SignedOutReason: Equatable, Sendable {
        case noCredentials
        /// The server answered 401: the session expired or was ended elsewhere.
        case expired
        /// The iPhone signed out and told the watch.
        case endedOnPhone
        case userSignedOut
    }

    public enum State: Equatable, Sendable {
        case restoring
        case active(Verification)
        case signedOut(SignedOutReason)
    }

    public enum Event: Sendable {
        case credentialsFound
        case noCredentials
        case validated
        case serverRejected
        case networkFailed
        case handoffSession
        case handoffSignedOut
        case userSignedOut
        case signedInOnDevice
    }

    public private(set) var state: State = .restoring

    public init(state: State = .restoring) { self.state = state }

    public var isActive: Bool { if case .active = state { true } else { false } }
    public var isSignedOut: Bool { if case .signedOut = state { true } else { false } }

    public mutating func apply(_ event: Event) {
        switch (state, event) {
        case (_, .userSignedOut): state = .signedOut(.userSignedOut)
        case (_, .handoffSignedOut): state = .signedOut(.endedOnPhone)
        case (_, .handoffSession), (_, .credentialsFound): state = .active(.unverified)
        case (_, .signedInOnDevice), (_, .validated): state = .active(.verified)
        case (_, .noCredentials): state = .signedOut(.noCredentials)
        case (.active, .serverRejected): state = .signedOut(.expired)
        case (.active(.verified), .networkFailed): break // one failed refresh does not make a verified session offline-only
        case (.active, .networkFailed): state = .active(.offline)
        case (.restoring, .serverRejected): state = .signedOut(.expired)
        case (.restoring, .networkFailed): state = .active(.offline)
        case (.signedOut, .serverRejected), (.signedOut, .networkFailed): break
        }
    }
}
