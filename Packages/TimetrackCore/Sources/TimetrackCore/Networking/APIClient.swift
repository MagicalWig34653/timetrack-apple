import Foundation

/// REST client for `/api/v1` (contract v0.10.3): cookie session `tt_session` plus `X-CSRF-Token` on every non-GET request.
/// Personal bearer tokens are not accepted by REST (only `/mcp`), so native clients always use the cookie session.
public actor APIClient: PreferencesService {
    public static let basePath = "/api/v1"

    public nonisolated let baseURL: URL
    private let transport: HTTPTransport
    private let decoder = JSONCoding.makeDecoder()
    private let encoder = JSONCoding.makeEncoder()
    private var csrfToken: String?
    private var moduleDisabledHandler: (@Sendable () -> Void)?
    /// Waits before a retry of a read that hit 503 `database_unavailable` (replaceable so tests do not sleep).
    private var retrySleeper: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    /// Reads (GET) answered with 503 `database_unavailable` are repeated up to this many times after the server's `Retry-After`.
    public static let maxUnavailableRetries = 2
    /// Upper bound for one wait, whatever the server asks for, so a screen never hangs for long.
    public static let maxRetryAfter: Duration = .seconds(10)
    public static let defaultRetryAfter: Duration = .seconds(2)

    public init(baseURL: URL, transport: HTTPTransport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Callback when any call answers 404 `module_disabled` (stores refresh their module switches).
    public func setModuleDisabledHandler(_ handler: (@Sendable () -> Void)?) { moduleDisabledHandler = handler }

    public func setRetrySleeper(_ sleeper: @escaping @Sendable (Duration) async throws -> Void) { retrySleeper = sleeper }

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
        var unavailableRetries = 0
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
            // 503 database_unavailable (contract v0.20.0): the database is briefly unreachable; `Retry-After` says when to ask again.
            // Only reads are repeated automatically; a write that may have been processed is reported to the caller instead.
            if response.statusCode == 503, failure.code == APIErrorCode.databaseUnavailable.rawValue, method == .get,
               unavailableRetries < Self.maxUnavailableRetries {
                unavailableRetries += 1
                do { try await retrySleeper(Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After"))) } catch { throw TimetrackError.cancelled }
                continue
            }
            throw failure
        }
    }

    /// `Retry-After` in seconds (the HTTP-date form is not used by the backend); missing or invalid values fall back to the default.
    static func retryDelay(_ header: String?) -> Duration {
        guard let header, let seconds = Int(header.trimmingCharacters(in: .whitespaces)), seconds >= 0 else { return defaultRetryAfter }
        return min(.seconds(seconds), maxRetryAfter)
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

    // MARK: - Work model correction (contract v0.16.0, ADR-0004 addendum) and system info (v0.19.0, ADR-0023)

    /// Replaces all editable fields of one version. `ifMatchVersion` is the model's `version` counter (412 `stale_version` when outdated).
    public func correctWorkModel(id: UUID, _ input: WorkModelInput, ifMatchVersion: Int?) async throws -> WorkModel {
        try await send(.put, "/work-models/\(id.uuidString.lowercased())", body: input,
                       headers: ifMatchVersion.map { ["If-Match": String($0)] } ?? [:])
    }

    /// Same check as the correction without saving: balance up to today before and after.
    public func previewWorkModelCorrection(id: UUID, _ input: WorkModelInput) async throws -> WorkModelPreview {
        try await send(.post, "/work-models/\(id.uuidString.lowercased())/preview", body: input)
    }

    /// Version and build data; members get the version fields only. Old backends answer 404.
    public func getSystemInfo() async throws -> SystemInfo { try await get("/system/info") }

    // MARK: - Places and device tokens (module `automation`, L2)

    public func createPlace(_ input: PlaceInput) async throws -> Place { try await send(.post, "/places", body: input) }

    public func updatePlace(id: UUID, _ input: PlaceInput) async throws -> Place {
        try await send(.put, "/places/\(id.uuidString.lowercased())", body: input)
    }

    public func listDeviceTokens() async throws -> [DeviceToken] { try await get("/me/device-tokens") }

    /// The clear text token is in the answer only once; the caller must store it immediately.
    public func createDeviceToken(name: String, expiresInDays: Int? = nil) async throws -> DeviceToken {
        struct Body: Encodable { let name: String; let expiresInDays: Int? }
        return try await send(.post, "/me/device-tokens", body: Body(name: name, expiresInDays: expiresInDays))
    }

    public func revokeDeviceToken(id: UUID) async throws { try await sendVoid(.delete, "/me/device-tokens/\(id.uuidString.lowercased())") }

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

    // MARK: - Time suggestions (Q1)

    /// Open suggestions. Reading also lets the backend notice an automation segment left open over midnight (flag + end suggestion).
    public func listTimeSuggestions() async throws -> [TimeSuggestion] { try await get("/time/suggestions") }

    /// Applies a suggestion once (an "end" suggestion closes its segment); the times may be overridden. A second call is 409.
    public func acceptTimeSuggestion(id: UUID, startedAt: Date? = nil, endedAt: Date? = nil) async throws -> Segment {
        struct Body: Encodable { let startedAt: Date?; let endedAt: Date? }
        return try await send(.post, "/time/suggestions/\(id.uuidString.lowercased())/accept", body: Body(startedAt: startedAt, endedAt: endedAt))
    }

    public func rejectTimeSuggestion(id: UUID) async throws {
        try await sendVoid(.post, "/time/suggestions/\(id.uuidString.lowercased())/reject")
    }

    // MARK: - Cancelled entries (SG1, contract 0.28.0)

    /// Cancelled entries, newest start first. `limit` 1...200.
    public func listCancelledSegments(from: Date? = nil, to: Date? = nil, limit: Int = 50, offset: Int = 0) async throws -> CancelledSegmentPage {
        var query = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]
        if let from { query.append(URLQueryItem(name: "from", value: JSONCoding.formatInstant(from))) }
        if let to { query.append(URLQueryItem(name: "to", value: JSONCoding.formatInstant(to))) }
        return try await get("/time/segments/cancelled", query: query)
    }

    /// Lifts the cancellation. 409 `segment_overlap` / `timer_already_running` / `segment_not_cancelled`, 412 `stale_version` (when `ifMatchVersion` is sent).
    public func restoreSegment(id: UUID, reason: String? = nil, ifMatchVersion: Int? = nil) async throws -> Segment {
        struct Body: Encodable { let reason: String? }
        var headers: [String: String] = [:]
        if let ifMatchVersion { headers["If-Match"] = String(ifMatchVersion) }
        return try await send(.post, "/time/segments/\(id.uuidString.lowercased())/restore", body: Body(reason: reason), headers: headers)
    }

    /// Permanently deletes one CANCELLED entry (409 `segment_not_cancelled` otherwise). Removes its correction log too; no tombstone.
    public func purgeSegment(id: UUID) async throws -> PurgeSummary {
        let data = try await perform(.delete, "/time/segments/\(id.uuidString.lowercased())", query: [URLQueryItem(name: "permanent", value: "true")])
        return try decode(PurgeSummary.self, from: data)
    }

    /// Bulk deletion of cancelled entries; `dryRun` only counts (the preview before the strong confirmation).
    public func purgeCancelledSegments(_ scope: PurgeScope, dryRun: Bool) async throws -> PurgeSummary {
        var query: [URLQueryItem] = []
        switch scope {
        case .ids(let ids): query.append(URLQueryItem(name: "ids", value: ids.map { $0.uuidString.lowercased() }.joined(separator: ",")))
        case .all: query.append(URLQueryItem(name: "all", value: "true"))
        case .range(let from, let to):
            if let from { query.append(URLQueryItem(name: "from", value: JSONCoding.formatInstant(from))) }
            if let to { query.append(URLQueryItem(name: "to", value: JSONCoding.formatInstant(to))) }
        }
        if dryRun { query.append(URLQueryItem(name: "dryRun", value: "true")) }
        return try decode(PurgeSummary.self, from: try await perform(.delete, "/time/segments/cancelled", query: query))
    }

    public func startTimer(clientEventId: UUID, kind: SegmentKind? = nil, placeId: UUID? = nil) async throws -> Segment {
        struct Body: Encodable { let clientEventId: UUID; let kind: SegmentKind?; let placeId: UUID? }
        return try await send(.post, "/time/timer/start", body: Body(clientEventId: clientEventId, kind: kind, placeId: placeId))
    }

    public func stopTimer(clientEventId: UUID) async throws -> Segment {
        struct Body: Encodable { let clientEventId: UUID }
        return try await send(.post, "/time/timer/stop", body: Body(clientEventId: clientEventId))
    }

    // MARK: - Planning (module `planning`)

    /// `hasAttachment` (contract v0.24.0) restricts the list server side to absences with (`true`) or without (`false`) attachments.
    public func listAbsences(from: LocalDay, to: LocalDay, hasAttachment: Bool? = nil) async throws -> [Absence] {
        var query = [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)]
        if let hasAttachment { query.append(URLQueryItem(name: "hasAttachment", value: hasAttachment ? "true" : "false")) }
        return try await get("/absences", query: query)
    }

    /// `GET /absences/{id}/attachments` (contract v0.24.0): the stored attachments of one absence.
    public func listAbsenceAttachments(id: UUID) async throws -> [FileMeta] {
        try await get("/absences/\(id.uuidString.lowercased())/attachments")
    }

    /// `GET /files/{id}`; with `inline` the server sends `Content-Disposition: inline` for previewable types and falls back to attachment otherwise.
    public func downloadFile(id: UUID, inline: Bool) async throws -> Data {
        let query = inline ? [URLQueryItem(name: "disposition", value: "inline")] : []
        return try await perform(.get, "/files/\(id.uuidString.lowercased())", query: query, headers: ["Accept": "*/*"])
    }

    public func getVacationBalance(year: Int) async throws -> VacationBalance {
        try await get("/vacation/balance", query: [URLQueryItem(name: "year", value: String(year))])
    }

    public func createAbsence(_ input: AbsenceInput) async throws -> Absence { try await send(.post, "/absences", body: input) }

    public func updateAbsence(id: UUID, _ input: AbsenceInput, ifMatchVersion: Int) async throws -> Absence {
        try await send(.put, "/absences/\(id.uuidString.lowercased())", body: input, headers: ["If-Match": String(ifMatchVersion)])
    }

    public func deleteAbsence(id: UUID) async throws { try await sendVoid(.delete, "/absences/\(id.uuidString.lowercased())") }

    public func getVacationSettings() async throws -> VacationSettings { try await get("/vacation/settings") }
    public func putVacationSettings(_ settings: VacationSettings) async throws -> VacationSettings { try await send(.put, "/vacation/settings", body: settings) }

    public func createVacationSnapshot(date: LocalDay, remainingHalfDays: Int) async throws -> VacationBalance {
        struct Body: Encodable { let date: LocalDay; let remainingHalfDays: Int }
        return try await send(.post, "/vacation/snapshots", body: Body(date: date, remainingHalfDays: remainingHalfDays))
    }

    public func createVacationAdjustment(date: LocalDay, halfDays: Int, reason: String) async throws -> VacationBalance {
        struct Body: Encodable { let date: LocalDay; let halfDays: Int; let reason: String }
        return try await send(.post, "/vacation/adjustments", body: Body(date: date, halfDays: halfDays, reason: reason))
    }

    public func listVacationEntries(year: Int) async throws -> VacationEntries {
        try await get("/vacation/entries", query: [URLQueryItem(name: "year", value: String(year))])
    }

    public func deleteVacationEntry(id: UUID) async throws { try await sendVoid(.delete, "/vacation/entries/\(id.uuidString.lowercased())") }

    /// Statutory holidays of the configured region (or `region`) plus the user's custom days for one year.
    public func listHolidays(year: Int, region: String? = nil) async throws -> [CalendarDay] {
        var query = [URLQueryItem(name: "year", value: String(year))]
        if let region { query.append(URLQueryItem(name: "region", value: region)) }
        return try await get("/calendar/holidays", query: query)
    }

    public func createCustomDay(_ input: CustomDayInput) async throws -> CalendarDay { try await send(.post, "/calendar/custom-days", body: input) }
    public func deleteCustomDay(id: UUID) async throws { try await sendVoid(.delete, "/calendar/custom-days/\(id.uuidString.lowercased())") }

    public func listPlanDays(from: LocalDay, to: LocalDay) async throws -> [PlanDay] {
        try await get("/plan/days", query: [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)])
    }

    public func putPlanDay(_ date: LocalDay, _ input: PlanDayInput) async throws -> PlanDay { try await send(.put, "/plan/days/\(date)", body: input) }
    public func deletePlanDay(_ date: LocalDay) async throws { try await sendVoid(.delete, "/plan/days/\(date)") }

    // MARK: - Week plan and vacation suggestions (K1, V2)

    public func getPlanWeek(_ isoWeek: String) async throws -> PlanWeek { try await get("/plan/weeks/\(isoWeek)") }

    public func putPlanWeek(_ isoWeek: String, _ input: PlanWeekInput) async throws -> PlanWeek {
        try await send(.put, "/plan/weeks/\(isoWeek)", body: input)
    }

    // MARK: - Plan shares (PL1, module planning)

    public func listShares() async throws -> [Share] { try await get("/shares") }

    public func createShare(_ input: ShareCreateInput) async throws -> Share { try await send(.post, "/shares", body: input) }

    public func updateShare(id: UUID, scopes: ShareScopes) async throws -> Share {
        try await send(.patch, "/shares/\(id.uuidString.lowercased())", body: ShareScopesInput(scopes: scopes))
    }

    /// Revokes at once; further views by the recipient answer 404.
    public func revokeShare(id: UUID) async throws { try await sendVoid(.delete, "/shares/\(id.uuidString.lowercased())") }

    public func listIncomingShares() async throws -> [IncomingShare] { try await get("/shares/incoming") }

    public func viewShared(shareId: UUID, from: LocalDay, to: LocalDay) async throws -> SharedView {
        try await get("/shares/incoming/\(shareId.uuidString.lowercased())/view", query: [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)])
    }

    /// Read-only: nothing is booked. Book a suggestion with `createAbsence`.
    public func getVacationSuggestions(_ query: VacationSuggestionQuery = VacationSuggestionQuery()) async throws -> VacationSuggestions {
        try await get("/vacation/suggestions", query: query.queryItems)
    }

    // MARK: - Berichtsheft (BH1, module `reports`)

    public func listLearningFields() async throws -> [LearningField] { try await get("/reports/learning-fields") }

    /// 409 `learning_field_exists` when the name is taken.
    public func createLearningField(_ input: LearningFieldInput) async throws -> LearningField { try await send(.post, "/reports/learning-fields", body: input) }

    public func updateLearningField(id: UUID, _ input: LearningFieldInput) async throws -> LearningField {
        try await send(.put, "/reports/learning-fields/\(id.uuidString.lowercased())", body: input)
    }

    /// Existing entries keep their name snapshot.
    public func deleteLearningField(id: UUID) async throws { try await sendVoid(.delete, "/reports/learning-fields/\(id.uuidString.lowercased())") }

    public func getReportWeek(_ ref: ReportWeekRef) async throws -> ReportWeek { try await get("/reports/weeks/\(ref.year)/\(ref.week)") }

    public func putReportWeekStatus(_ ref: ReportWeekRef, status: ReportStatus) async throws -> ReportWeek {
        struct Body: Encodable { let status: ReportStatus }
        return try await send(.put, "/reports/weeks/\(ref.year)/\(ref.week)", body: Body(status: status))
    }

    /// Copyable plain text in the standard format (`text/plain; charset=utf-8`).
    public func getReportWeekText(_ ref: ReportWeekRef) async throws -> String {
        let data = try await perform(.get, "/reports/weeks/\(ref.year)/\(ref.week)/text", headers: ["Accept": "text/plain"])
        return String(decoding: data, as: UTF8.self)
    }

    public func createReportEntry(_ input: ReportEntryInput) async throws -> ReportEntry { try await send(.post, "/reports/entries", body: input) }

    /// `If-Match` carries the entry's `version`; 412 `stale_version` when it changed elsewhere.
    public func updateReportEntry(id: UUID, _ input: ReportEntryInput, ifMatchVersion: Int) async throws -> ReportEntry {
        try await send(.put, "/reports/entries/\(id.uuidString.lowercased())", body: input, headers: ["If-Match": String(ifMatchVersion)])
    }

    public func deleteReportEntry(id: UUID) async throws { try await sendVoid(.delete, "/reports/entries/\(id.uuidString.lowercased())") }

    public func listReportSources(_ ref: ReportWeekRef) async throws -> [ReportSource] {
        try await get("/reports/sources", query: [URLQueryItem(name: "year", value: String(ref.year)), URLQueryItem(name: "week", value: String(ref.week))])
    }

    public func createReportSource(_ input: ReportSourceInput) async throws -> ReportSource { try await send(.post, "/reports/sources", body: input) }

    public func deleteReportSource(id: UUID) async throws { try await sendVoid(.delete, "/reports/sources/\(id.uuidString.lowercased())") }

    /// `POST /files` (multipart, field `file`). 413 `file_too_large` and 415 `unsupported_type` come back as API errors.
    public func uploadFile(name: String, contentType: String, data: Data) async throws -> FileMeta {
        let boundary = "tt-\(UUID().uuidString)"
        var body = Data()
        let safeName = name.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let answer = try await perform(.post, "/files", body: body, headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"])
        return try decode(FileMeta.self, from: answer)
    }

    // MARK: - Evaluation and account

    /// One-call week overview (core feature, no module needed).
    public func getTimeWeek(_ isoWeek: String) async throws -> TimeWeek { try await get("/time/weeks/\(isoWeek)") }

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

    // MARK: - Preferences (account-level appearance, contract v0.14.0)

    public func getPreferences() async throws -> Preferences { try await get("/me/preferences") }

    /// Merge-patch: only the keys in `patch` change. Answers the full object.
    public func updatePreferences(_ patch: PreferencesPatch) async throws -> Preferences { try await send(.patch, "/me/preferences", body: patch) }

    public func getTimeAccount(asOf: LocalDay? = nil) async throws -> TimeAccount {
        try await get("/time/account", query: asOf.map { [URLQueryItem(name: "asOf", value: $0)] } ?? [])
    }
}
