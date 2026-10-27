import Foundation

/// Stable English error codes of the contract (`{ "error": { "code", "message" } }`). Unknown codes stay available as raw strings.
public enum APIErrorCode: String, Sendable, CaseIterable {
    case badRequest = "bad_request"
    case unauthorized
    case forbidden
    case notFound = "not_found"
    case conflict
    case handleTaken = "handle_taken"
    case lastPasskey = "last_passkey"
    case tooManyRequests = "too_many_requests"
    case notImplemented = "not_implemented"
    case invalidCode = "invalid_code"
    case csrfInvalid = "csrf_invalid"
    case recoverySessionRestricted = "recovery_session_restricted"
    case reauthRequired = "reauth_required"
    case notReady = "not_ready"
    case moduleDisabled = "module_disabled"
    case moduleLocked = "module_locked"
    case timerAlreadyRunning = "timer_already_running"
    case noRunningTimer = "no_running_timer"
    case segmentOverlap = "segment_overlap"
    case staleVersion = "stale_version"
    /// SG1 (contract 0.28.0): restoring/purging an entry that is not cancelled (409); a bulk purge without any selection (400).
    case segmentNotCancelled = "segment_not_cancelled"
    case purgeScopeRequired = "purge_scope_required"
    case modelOverlap = "model_overlap"
    case rangeTooLarge = "range_too_large"
    case absenceOverlap = "absence_overlap"
    case insufficientScope = "insufficient_scope"
    /// 503 with `Retry-After`: the database is briefly unreachable (contract v0.20.0).
    case databaseUnavailable = "database_unavailable"
    case invalid
    case invalidWeek = "invalid_week"
    case weekDayInvalid = "week_day_invalid"
    case planTimeInvalid = "plan_time_invalid"
    case planBreakInvalid = "plan_break_invalid"
    /// Plan shares (PL1): unknown recipient (404), second share to the same account (409), share to oneself (400).
    case recipientNotFound = "recipient_not_found"
    case shareExists = "share_exists"
    case cannotShareWithSelf = "cannot_share_with_self"
    /// Berichtsheft (BH1): a learning field with this name exists (409); upload limits (413/415).
    case learningFieldExists = "learning_field_exists"
    case fileTooLarge = "file_too_large"
    case unsupportedType = "unsupported_type"
    /// Vacation request template (AB1, contract v0.25.0): no template stored (409), mapping above 64 KB (413).
    case noTemplate = "no_template"
    case mappingTooLarge = "mapping_too_large"
    /// P14 (contract 0.33.0): APNs is not configured on the server (501), device limit reached (409), APNs refused the test push (502).
    case pushUnavailable = "push_unavailable"
    case tooManyPushDevices = "too_many_push_devices"
    case pushFailed = "push_failed"
    /// N2 (contract 0.31.0): more than 10 active calendar feeds (409).
    case tooManyCalendarFeeds = "too_many_calendar_feeds"
}

/// Everything that can go wrong in a client call. No request or response bodies that could hold secrets are kept in descriptions.
public enum TimetrackError: Error, Sendable, Equatable {
    /// HTTP error with the contract's error payload (`code` is the raw backend string).
    case api(status: Int, code: String, message: String)
    /// Transport failure (offline, DNS, TLS, timeout); retrying with the same `clientEventId` is safe.
    case network(URLError.Code)
    /// The server answered with a body that does not match the contract.
    case decoding(String)
    case invalidServerURL
    case cancelled
    /// Passkey flow cancelled or unavailable.
    case passkey(String)

    public var status: Int? {
        if case .api(let status, _, _) = self { return status }
        return nil
    }

    public var code: String? {
        if case .api(_, let code, _) = self { return code }
        return nil
    }

    public var knownCode: APIErrorCode? { code.flatMap(APIErrorCode.init(rawValue:)) }

    public var isNetworkError: Bool {
        if case .network = self { return true }
        return false
    }

    public var isUnauthorized: Bool { status == 401 }

    /// German text for the UI, keyed by stable codes (String Catalog `Localizable.xcstrings`, German is the source language).
    /// Looks the key up in the compiled bundle; falls back to the raw String Catalog, which is what SwiftPM test runs
    /// (and `Bundle.module` resolved to the build directory) provide instead of compiled `.strings` files.
    private static func text(_ key: String) -> String {
        let compiled = Bundle.module.localizedString(forKey: key, value: nil, table: nil)
        if compiled != key { return compiled }
        return rawCatalog[key] ?? key
    }

    private static let rawCatalog: [String: String] = {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: [String: Any]] else { return [:] }
        var result: [String: String] = [:]
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String: [String: Any]]
            let unit = localizations?["de"]?["stringUnit"] as? [String: Any]
            if let value = unit?["value"] as? String { result[key] = value }
        }
        return result
    }()

    public var germanDescription: String {
        switch self {
        case .api(_, let code, _):
            if let known = APIErrorCode(rawValue: code) {
                return Self.text("error.\(known.rawValue)")
            }
            return Self.text("error.http")
        case .network:
            return Self.text("error.network")
        case .decoding:
            return Self.text("error.decoding")
        case .invalidServerURL:
            return Self.text("error.invalid_server_url")
        case .cancelled:
            return Self.text("error.cancelled")
        case .passkey:
            return Self.text("error.passkey")
        }
    }
}

extension TimetrackError: LocalizedError {
    public var errorDescription: String? { germanDescription }
}

struct ErrorEnvelope: Decodable {
    struct Body: Decodable { let code: String?; let message: String? }
    let error: Body?
}
