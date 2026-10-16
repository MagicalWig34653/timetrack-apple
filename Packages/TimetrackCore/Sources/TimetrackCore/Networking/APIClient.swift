import Foundation

/// REST client for `/api/v1` (contract v0.10.3): cookie session `tt_session` plus `X-CSRF-Token` on every non-GET request.
/// Personal bearer tokens are not accepted by REST (only `/mcp`), so native clients always use the cookie session.
public actor APIClient {
    public static let basePath = "/api/v1"

    public nonisolated let baseURL: URL
    private let transport: HTTPTransport
    private let decoder = JSONCoding.makeDecoder()
    private let encoder = JSONCoding.makeEncoder()
    private var csrfToken: String?
    private var moduleDisabledHandler: (@Sendable () -> Void)?

    public init(baseURL: URL, transport: HTTPTransport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Callback when any call answers 404 `module_disabled` (stores refresh their module switches).
    public func setModuleDisabledHandler(_ handler: (@Sendable () -> Void)?) { moduleDisabledHandler = handler }

    public func setCSRFToken(_ token: String?) { csrfToken = token }
    public var currentCSRFToken: String? { csrfToken }

    // MARK: - Core request

    private enum Method: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

    private func makeRequest(_ method: Method, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, headers: [String: String] = [:]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw TimetrackError.invalidServerURL }
        let prefix = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = prefix + Self.basePath + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw TimetrackError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != .get, let csrfToken { request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    private func perform(_ method: Method, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, headers: [String: String] = [:]) async throws -> Data {
        var refreshedCSRF = false
        while true {
            try Task.checkCancellation()
            let request = try makeRequest(method, path, query: query, body: body, headers: headers)
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch is CancellationError {
                throw TimetrackError.cancelled
            } catch let error as URLError {
                if error.code == .cancelled { throw TimetrackError.cancelled }
                throw TimetrackError.network(error.code)
            }
            if (200..<300).contains(response.statusCode) { return data }
            let failure = parseError(status: response.statusCode, data: data)
            // A rejected CSRF token means the request was not processed: refresh the token once and replay.
            if failure.code == APIErrorCode.csrfInvalid.rawValue, method != .get, !refreshedCSRF, path != "/auth/session" {
                refreshedCSRF = true
                if (try? await refreshSession()) != nil { continue }
            }
            if response.statusCode == 404, failure.code == APIErrorCode.moduleDisabled.rawValue { moduleDisabledHandler?() }
            throw failure
        }
    }

    private func parseError(status: Int, data: Data) -> TimetrackError {
        var code = "http_\(status)"
        var message = HTTPURLResponse.localizedString(forStatusCode: status)
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data), let body = envelope.error {
            if let value = body.code, !value.isEmpty { code = value }
            if let value = body.message, !value.isEmpty { message = value }
        }
        return .api(status: status, code: code, message: message)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw TimetrackError.decoding(String(describing: type))
        }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try decode(T.self, from: try await perform(.get, path, query: query))
    }

    private func send<T: Decodable, B: Encodable>(_ method: Method, _ path: String, body: B, query: [URLQueryItem] = [], headers: [String: String] = [:]) async throws -> T {
        let payload = try encoder.encode(body)
        return try decode(T.self, from: try await perform(method, path, query: query, body: payload, headers: headers))
    }

    private func sendVoid<B: Encodable>(_ method: Method, _ path: String, body: B, query: [URLQueryItem] = []) async throws {
        _ = try await perform(method, path, query: query, body: try encoder.encode(body))
    }

    private func sendVoid(_ method: Method, _ path: String, query: [URLQueryItem] = []) async throws {
        _ = try await perform(method, path, query: query)
    }

    private struct Empty: Encodable {}

    // MARK: - Session

    /// Loads the session and remembers its CSRF token.
    @discardableResult
    public func refreshSession() async throws -> Session {
        let session: Session = try await get("/auth/session")
        csrfToken = session.csrfToken
        return session
    }

    public func logout() async throws {
        try await sendVoid(.delete, "/auth/session")
        csrfToken = nil
    }

    private func sessionCall(_ path: String, body: some Encodable) async throws -> Session {
        let session: Session = try await send(.post, path, body: body)
        csrfToken = session.csrfToken
        return session
    }

    // MARK: - Authentication

    public func loginOptions() async throws -> WebAuthnOptions { try await send(.post, "/auth/login/options", body: Empty()) }

    public func loginVerify(challengeId: String, credential: JSONValue) async throws -> Session {
        struct Body: Encodable { let challengeId: String; let credential: JSONValue }
        return try await sessionCall("/auth/login/verify", body: Body(challengeId: challengeId, credential: credential))
    }

    public func recoveryStart(method: RecoveryMethod, identifier: String) async throws -> RecoveryStart {
        struct Body: Encodable { let method: RecoveryMethod; let identifier: String }
        return try await send(.post, "/auth/recovery/start", body: Body(method: method, identifier: identifier))
    }

    public func recoveryComplete(recoveryId: String, proof: String) async throws -> Session {
        struct Body: Encodable { let recoveryId: String; let proof: String }
        return try await sessionCall("/auth/recovery/complete", body: Body(recoveryId: recoveryId, proof: proof))
    }

    public func addPasskeyOptions() async throws -> WebAuthnOptions { try await send(.post, "/me/passkeys/options", body: Empty()) }

    /// A successful call inside a recovery session upgrades it to a normal session (contract decision 3).
    public func addPasskeyVerify(challengeId: String, credential: JSONValue, name: String?) async throws {
        struct Body: Encodable { let challengeId: String; let credential: JSONValue; let passkeyName: String? }
        let _: JSONValue = try await send(.post, "/me/passkeys/verify", body: Body(challengeId: challengeId, credential: credential, passkeyName: name))
    }

    // MARK: - Modules, work model, places

    public func listModules() async throws -> [ModuleStatus] { try await get("/modules") }
    public func listWorkModels() async throws -> [WorkModel] { try await get("/work-models") }
    public func listPlaces() async throws -> [Place] { try await get("/places") }

    // MARK: - Segments and timer

    public func listSegments(from: Date, to: Date, includeVoided: Bool = false) async throws -> [Segment] {
        var query = [URLQueryItem(name: "from", value: JSONCoding.formatInstant(from)), URLQueryItem(name: "to", value: JSONCoding.formatInstant(to))]
        if includeVoided { query.append(URLQueryItem(name: "includeVoided", value: "true")) }
        return try await get("/time/segments", query: query)
    }

    public func createSegment(_ input: SegmentInput) async throws -> Segment { try await send(.post, "/time/segments", body: input) }

    public func correctSegment(id: UUID, _ correction: SegmentCorrection, ifMatchVersion: Int) async throws -> Segment {
        try await send(.patch, "/time/segments/\(id.uuidString.lowercased())", body: correction, headers: ["If-Match": String(ifMatchVersion)])
    }

    public func voidSegment(id: UUID, reason: String) async throws {
        try await sendVoid(.delete, "/time/segments/\(id.uuidString.lowercased())", query: [URLQueryItem(name: "reason", value: reason)])
    }

    public func currentTimer() async throws -> Segment? { try await get("/time/timer") }

    public func startTimer(clientEventId: UUID, kind: SegmentKind? = nil, placeId: UUID? = nil) async throws -> Segment {
        struct Body: Encodable { let clientEventId: UUID; let kind: SegmentKind?; let placeId: UUID? }
        return try await send(.post, "/time/timer/start", body: Body(clientEventId: clientEventId, kind: kind, placeId: placeId))
    }

    public func stopTimer(clientEventId: UUID) async throws -> Segment {
        struct Body: Encodable { let clientEventId: UUID }
        return try await send(.post, "/time/timer/stop", body: Body(clientEventId: clientEventId))
    }

    // MARK: - Planning (module `planning`, read-only here)

    public func listAbsences(from: LocalDay, to: LocalDay) async throws -> [Absence] {
        try await get("/absences", query: [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)])
    }

    public func getVacationBalance(year: Int) async throws -> VacationBalance {
        try await get("/vacation/balance", query: [URLQueryItem(name: "year", value: String(year))])
    }

    // MARK: - Evaluation and account

    /// The API allows at most 93 days per request; longer ranges are loaded in chunks.
    public static let maxDaysPerRequest = 93

    public func listDays(from: LocalDay, to: LocalDay) async throws -> [DayEvaluation] {
        var result: [DayEvaluation] = []
        for range in try LocalDays.chunks(from: from, to: to, maxDays: Self.maxDaysPerRequest) {
            let part: [DayEvaluation] = try await get("/time/days", query: [URLQueryItem(name: "from", value: range.from), URLQueryItem(name: "to", value: range.to)])
            result += part
        }
        return result
    }

    public func getDay(_ date: LocalDay) async throws -> DayEvaluation { try await get("/time/days/\(date)") }

    public func getTimeAccount(asOf: LocalDay? = nil) async throws -> TimeAccount {
        try await get("/time/account", query: asOf.map { [URLQueryItem(name: "asOf", value: $0)] } ?? [])
    }
}
