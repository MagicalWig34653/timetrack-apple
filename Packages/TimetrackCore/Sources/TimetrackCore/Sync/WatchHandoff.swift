import Foundation

/// What the iPhone hands to the watch: the server and the opaque session cookie value, nothing else.
///
/// Security notes: the payload travels only over WatchConnectivity (`updateApplicationContext`, which Apple transports
/// between the paired devices over the system's encrypted link). It is never written to the application's defaults, files or logs.
/// On the iPhone the values come from the Keychain; on the watch they are stored in the watch's own Keychain through `SecretStore`.
public enum HandoffPayload: Sendable, Equatable {
    case session(server: URL, cookie: String)
    case signedOut

    static let versionKey = "v"
    static let serverKey = "server"
    static let cookieKey = "cookie"
    static let stampKey = "stamp"
    static let currentVersion = "1"

    /// Context dictionary for `updateApplicationContext`; `stamp` orders messages (ISO-8601 with fractional seconds).
    public func encoded(stamp: Date) -> [String: String] {
        var result = [Self.versionKey: Self.currentVersion, Self.stampKey: Self.format(stamp)]
        if case .session(let server, let cookie) = self {
            result[Self.serverKey] = server.absoluteString
            result[Self.cookieKey] = cookie
        }
        return result
    }

    /// Returns nil for unknown versions or malformed contexts (including the empty initial context).
    public static func decode(_ context: [String: String]) -> (payload: HandoffPayload, stamp: Date)? {
        guard context[versionKey] == currentVersion, let stampText = context[stampKey], let stamp = parse(stampText) else { return nil }
        guard let server = context[serverKey], let cookie = context[cookieKey] else { return (.signedOut, stamp) }
        guard !cookie.isEmpty, let url = URL(string: server), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return (.session(server: url, cookie: cookie), stamp)
    }

    private static func format(_ date: Date) -> String { date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) }
    private static func parse(_ text: String) -> Date? { try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) }
}

public enum WatchChannelEvent: Sendable, Equatable {
    /// The session finished activating (a context may already be waiting in `receivedContext`).
    case activated
    case context([String: String])
    /// The watch asked the iPhone to send the session again.
    case resendRequested
}

/// Minimal surface of `WCSession` so handoff logic is testable without devices.
public protocol WatchSessionChannel: Sendable {
    func activate(handler: @escaping @Sendable (WatchChannelEvent) -> Void)
    func send(context: [String: String]) throws
    /// Last context delivered to this device (watch side).
    var receivedContext: [String: String] { get }
    /// Best-effort live request to the counterpart; ignored when it is not reachable.
    func requestResend()
    /// iPhone side: whether a watch with the app is paired and whether it can be reached right now.
    var link: WatchLinkState { get }
}

public enum WatchLinkState: Sendable, Equatable {
    /// No paired watch, no installed watch app, or WatchConnectivity is unavailable.
    case notPaired
    /// Paired, but the watch app cannot be reached right now (context delivery is queued by the system).
    case unreachable
    case reachable
}

/// Outcome of a manual "send session to watch" action.
public enum WatchHandoffResult: Sendable, Equatable {
    case notPaired
    case notSignedIn
    /// Paired but not reachable: the context was queued and arrives when the watch app next runs.
    case queuedUnreachable
    case sent
    case failed
}

/// iPhone side: pushes the current session to the watch whenever it changes or the watch asks.
public actor WatchHandoffSender {
    private let channel: WatchSessionChannel
    private let secrets: SecretStore
    private let now: @Sendable () -> Date
    /// nil until the app knows its state (still restoring or offline); nothing is pushed before that so a launch never signs the watch out.
    private var isSignedIn: Bool?
    private var lastStamp: Date?

    public init(channel: WatchSessionChannel, secrets: SecretStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.channel = channel
        self.secrets = secrets
        self.now = now
    }

    public func start() {
        channel.activate { [weak self] event in
            switch event {
            case .activated, .resendRequested: Task { await self?.push() }
            case .context: break
            }
        }
    }

    /// Call whenever the app's sign-in state changes. Recovery-restricted sessions count as signed out.
    public func update(isSignedIn: Bool) {
        self.isSignedIn = isSignedIn
        push()
    }

    /// Manual push ("Sitzung an Uhr senden"). Never signs the watch out: without an active session nothing is sent.
    public func sendNow() -> WatchHandoffResult {
        let link = channel.link
        guard link != .notPaired else { return .notPaired }
        guard isSignedIn == true, secrets.read(SecretKey.serverURL) != nil, secrets.read(SecretKey.sessionCookie) != nil else { return .notSignedIn }
        guard push() else { return .failed }
        return link == .reachable ? .sent : .queuedUnreachable
    }

    @discardableResult
    private func push() -> Bool {
        guard let isSignedIn else { return false }
        let payload: HandoffPayload
        if isSignedIn, let server = secrets.read(SecretKey.serverURL).flatMap({ URL(string: $0) }), let cookie = secrets.read(SecretKey.sessionCookie) {
            payload = .session(server: server, cookie: cookie)
        } else {
            payload = .signedOut
        }
        // Strictly increasing stamps so the watch can discard stale deliveries.
        var stamp = now()
        if let lastStamp, stamp <= lastStamp { stamp = lastStamp.addingTimeInterval(0.001) }
        lastStamp = stamp
        do { try channel.send(context: payload.encoded(stamp: stamp)); return true } catch { return false }
    }
}

/// Watch side: turns incoming contexts into session changes. The closures store/clear the session (Keychain via `AuthService`).
public actor WatchHandoffReceiver {
    private nonisolated let channel: WatchSessionChannel
    private let secrets: SecretStore
    private let onSession: @Sendable (URL, String) async -> Void
    private let onSignedOut: @Sendable () async -> Void
    static let stampKey = "handoff-stamp"

    public init(channel: WatchSessionChannel, secrets: SecretStore,
                onSession: @escaping @Sendable (URL, String) async -> Void,
                onSignedOut: @escaping @Sendable () async -> Void) {
        self.channel = channel
        self.secrets = secrets
        self.onSession = onSession
        self.onSignedOut = onSignedOut
    }

    public func start() {
        channel.activate { [weak self] event in
            switch event {
            case .activated: Task { await self?.applyReceived() }
            case .context(let context): Task { await self?.apply(context, force: false) }
            case .resendRequested: break
            }
        }
    }

    /// "Sitzung vom iPhone übernehmen": re-applies whatever the iPhone sent last (even if seen before) and asks it to resend.
    public func pullNow() async {
        channel.requestResend()
        await apply(channel.receivedContext, force: true)
    }

    private func applyReceived() async { await apply(channel.receivedContext, force: false) }

    /// Applies a context unless an equal or newer one was applied before. Returns whether it changed anything.
    @discardableResult
    func apply(_ context: [String: String], force: Bool) async -> Bool {
        guard let (payload, stamp) = HandoffPayload.decode(context) else { return false }
        if !force, let seen = secrets.read(Self.stampKey).flatMap({ Double($0) }), stamp.timeIntervalSince1970 <= seen { return false }
        secrets.write(String(stamp.timeIntervalSince1970), for: Self.stampKey)
        switch payload {
        case .session(let server, let cookie): await onSession(server, cookie)
        case .signedOut: await onSignedOut()
        }
        return true
    }
}
