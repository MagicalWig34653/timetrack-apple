import Foundation

/// Injectable transport so tests can run the client without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Same as `send`, reporting the upload progress (0...1) of the request body. Transports without progress ignore the handler.
    func send(_ request: URLRequest, progress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse)
}

public extension HTTPTransport {
    func send(_ request: URLRequest, progress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        try await send(request)
    }
}

/// Forwards `didSendBodyData` of one task to a progress handler.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let handler: @Sendable (Double) -> Void
    init(_ handler: @escaping @Sendable (Double) -> Void) { self.handler = handler }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        handler(min(max(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 0), 1))
    }
}

/// Where the opaque session cookie value is kept between launches (Keychain in the apps).
public protocol SessionCookieJar: Sendable {
    func sessionCookieValue(for baseURL: URL) -> String?
    func setSessionCookie(_ value: String, for baseURL: URL)
    func clearSessionCookie(for baseURL: URL)
}

public func sessionCookieName(for baseURL: URL) -> String {
    baseURL.scheme == "https" ? "__Host-tt_session" : "tt_session"
}

/// URLSession-based transport with a private cookie store (no sharing with other apps or browsers).
public final class URLSessionTransport: HTTPTransport, SessionCookieJar, @unchecked Sendable {
    private let session: URLSession
    private let cookies: HTTPCookieStorage

    public convenience init(timeout: TimeInterval = 30) {
        self.init(configuration: .ephemeral, timeout: timeout)
    }

    init(configuration: URLSessionConfiguration, timeout: TimeInterval = 30) {
        // The ephemeral configuration owns a private in-memory store; a hand-made HTTPCookieStorage() is not honoured by URLSession.
        cookies = configuration.httpCookieStorage ?? HTTPCookieStorage()
        cookies.cookieAcceptPolicy = .always
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await send(request, progress: nil)
    }

    public func send(_ request: URLRequest, progress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        if let progress {
            (data, response) = try await session.data(for: request, delegate: UploadProgressDelegate(progress))
        } else {
            (data, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    public func sessionCookieValue(for baseURL: URL) -> String? {
        cookies.cookies(for: baseURL)?.first { $0.name == sessionCookieName(for: baseURL) }?.value
    }

    public func setSessionCookie(_ value: String, for baseURL: URL) {
        clearSessionCookie(for: baseURL)
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: sessionCookieName(for: baseURL), .value: value, .path: "/", .originURL: baseURL,
        ]
        if baseURL.scheme == "https" { properties[.secure] = "TRUE" }
        if let cookie = HTTPCookie(properties: properties) { cookies.setCookie(cookie) }
    }

    public func clearSessionCookie(for baseURL: URL) {
        // Inspect HTTPS too so a stale Secure cookie is removed when the server switches to HTTP.
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        let lookupURL = components?.url ?? baseURL
        for cookie in cookies.cookies(for: lookupURL) ?? []
        where cookie.name == "tt_session" || cookie.name == "__Host-tt_session" {
            cookies.deleteCookie(cookie)
        }
    }
}
