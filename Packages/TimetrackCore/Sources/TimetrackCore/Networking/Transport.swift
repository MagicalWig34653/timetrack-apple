import Foundation

/// Injectable transport so tests can run the client without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Where the opaque `tt_session` cookie value is kept between launches (Keychain in the apps).
public protocol SessionCookieJar: Sendable {
    func sessionCookieValue(for baseURL: URL) -> String?
    func setSessionCookie(_ value: String, for baseURL: URL)
    func clearSessionCookie(for baseURL: URL)
}

public let sessionCookieName = "tt_session"

/// URLSession-based transport with a private cookie store (no sharing with other apps or browsers).
public final class URLSessionTransport: HTTPTransport, SessionCookieJar, @unchecked Sendable {
    private let session: URLSession
    private let cookies: HTTPCookieStorage

    public init(timeout: TimeInterval = 30) {
        cookies = HTTPCookieStorage()
        cookies.cookieAcceptPolicy = .always
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = cookies
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    public func sessionCookieValue(for baseURL: URL) -> String? {
        cookies.cookies(for: baseURL)?.first { $0.name == sessionCookieName }?.value
    }

    public func setSessionCookie(_ value: String, for baseURL: URL) {
        clearSessionCookie(for: baseURL)
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: sessionCookieName, .value: value, .path: "/", .domain: baseURL.host() ?? "",
        ]
        if baseURL.scheme == "https" { properties[.secure] = "TRUE" }
        if let cookie = HTTPCookie(properties: properties) { cookies.setCookie(cookie) }
    }

    public func clearSessionCookie(for baseURL: URL) {
        for cookie in cookies.cookies(for: baseURL) ?? [] where cookie.name == sessionCookieName { cookies.deleteCookie(cookie) }
    }
}
