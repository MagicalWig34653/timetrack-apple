#if canImport(WatchConnectivity) && !os(macOS)
import Foundation
import WatchConnectivity

/// `WatchSessionChannel` backed by `WCSession.default`. Secrets in the context are encrypted in transit by the system and
/// are only ever held in memory here; callers persist them in the Keychain.
public final class WCSessionChannel: NSObject, WatchSessionChannel, WCSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (WatchChannelEvent) -> Void)?

    public override init() { super.init() }

    private func emit(_ event: WatchChannelEvent) { lock.withLock { handler }?(event) }

    public func activate(handler: @escaping @Sendable (WatchChannelEvent) -> Void) {
        guard WCSession.isSupported() else { return }
        lock.withLock { self.handler = handler }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    public func send(context: [String: String]) throws {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        try session.updateApplicationContext(context)
    }

    public var receivedContext: [String: String] {
        guard WCSession.isSupported() else { return [:] }
        return WCSession.default.receivedApplicationContext.compactMapValues { $0 as? String }
    }

    public func requestResend() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "session"], replyHandler: nil, errorHandler: nil)
    }

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { emit(.activated) }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        emit(.context(applicationContext.compactMapValues { $0 as? String }))
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "session" { emit(.resendRequested) }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    public func sessionWatchStateDidChange(_ session: WCSession) { if session.isWatchAppInstalled { emit(.activated) } }
    #endif
}
#endif
