import Foundation
import Testing
@testable import TimetrackCore

@Suite struct SessionCookieTests {
    private func makeTransport() -> (URLSessionTransport, HTTPCookieStorage) {
        let configuration = URLSessionConfiguration.ephemeral
        return (URLSessionTransport(configuration: configuration), configuration.httpCookieStorage!)
    }

    private func seedCookies(_ storage: HTTPCookieStorage, server: URL) throws {
        for name in ["tt_session", "__Host-tt_session", "unrelated"] {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: name, .originURL: server, .path: "/",
            ]
            if name == "__Host-tt_session" { properties[.secure] = "TRUE" }
            let cookie = try #require(HTTPCookie(properties: properties))
            storage.setCookie(cookie)
        }
        #expect(Set(storage.cookies?.map(\.name) ?? []) == ["tt_session", "__Host-tt_session", "unrelated"])
    }

    @Test(arguments: ["https", "http"])
    func readsAndRestoresCookieForServerScheme(scheme: String) throws {
        let server = try #require(URL(string: "\(scheme)://timetrack.example.org"))
        let expectedName = scheme == "https" ? "__Host-tt_session" : "tt_session"
        let (transport, storage) = makeTransport()
        try seedCookies(storage, server: server)
        #expect(sessionCookieName(for: server) == expectedName)
        #expect(transport.sessionCookieValue(for: server) == expectedName)

        transport.setSessionCookie("restored", for: server)
        let cookie = try #require(storage.cookies?.first { $0.name == expectedName })
        #expect(cookie.value == "restored")
        #expect(cookie.path == "/")
        #expect(cookie.isSecure == (scheme == "https"))
        #expect(cookie.domain == "timetrack.example.org")
        #expect(transport.sessionCookieValue(for: server) == "restored")
        #expect(storage.cookies?.contains { $0.name == (scheme == "https" ? "tt_session" : "__Host-tt_session") } == false)
    }

    @Test func httpsDoesNotReadLegacyCookie() throws {
        let server = try #require(URL(string: "https://timetrack.example.org"))
        let (transport, storage) = makeTransport()
        storage.setCookie(try #require(HTTPCookie(properties: [
            .name: "tt_session", .value: "legacy", .originURL: server, .path: "/",
        ])))
        #expect(transport.sessionCookieValue(for: server) == nil)
    }

    @Test(arguments: ["https", "http"])
    func clearingRemovesBothNamesAndKeepsOtherCookies(scheme: String) throws {
        let server = try #require(URL(string: "\(scheme)://timetrack.example.org"))
        let (transport, storage) = makeTransport()
        try seedCookies(storage, server: server)
        transport.clearSessionCookie(for: server)
        transport.clearSessionCookie(for: server)
        #expect(storage.cookies?.map(\.name) == ["unrelated"])
        #expect(transport.sessionCookieValue(for: server) == nil)
    }

    @Test(arguments: ["https", "http"], [false, true])
    func sessionEndClearsBothNamesAndKeychain(scheme: String, localOnly: Bool) async throws {
        let server = try #require(URL(string: "\(scheme)://timetrack.example.org"))
        let (transport, storage) = makeTransport()
        let secrets = InMemorySecretStore()
        let auth = AuthService(secrets: secrets, transport: transport)
        // Watch transfer and Keychain restoration use the same URL-derived name.
        await auth.importSession(server: server, cookieValue: "from-phone")
        #expect(await auth.optimisticClient() != nil)
        #expect(transport.sessionCookieValue(for: server) == "from-phone")
        try seedCookies(storage, server: server)
        if localOnly {
            await auth.discardSession()
        } else {
            // No network request is needed to verify local logout cleanup.
            let signedOut = AuthService(secrets: secrets, transport: transport)
            await signedOut.signOut()
        }
        #expect(storage.cookies?.map(\.name) == ["unrelated"])
        #expect(secrets.read(SecretKey.sessionCookie) == nil)
    }
}
