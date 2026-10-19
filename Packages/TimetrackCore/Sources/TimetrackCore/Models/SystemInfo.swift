import Foundation

/// `GET /system/info` (contract v0.19.0+, ADR-0023). Members receive only the version fields of `backend`; administrators also
/// get the operational fields. Unknown future fields are ignored.
public struct SystemInfo: Decodable, Sendable, Equatable {
    public struct Backend: Decodable, Sendable, Equatable {
        public let version: String
        public let revision: String?
        public let revisionShort: String?
        /// ISO-8601 (UTC) or nil for a local build.
        public let buildDate: String?
        public let apiVersion: String
        // Administrators only:
        public let database: String?
        public let schemaMigrations: Int?
        public let migrationsPending: Bool?
        public let uptimeSeconds: Int?
        public let replicaId: String?

        public init(version: String, revision: String? = nil, revisionShort: String? = nil, buildDate: String? = nil, apiVersion: String,
                    database: String? = nil, schemaMigrations: Int? = nil, migrationsPending: Bool? = nil, uptimeSeconds: Int? = nil, replicaId: String? = nil) {
            self.version = version
            self.revision = revision
            self.revisionShort = revisionShort
            self.buildDate = buildDate
            self.apiVersion = apiVersion
            self.database = database
            self.schemaMigrations = schemaMigrations
            self.migrationsPending = migrationsPending
            self.uptimeSeconds = uptimeSeconds
            self.replicaId = replicaId
        }

        /// True when the answer carries the administrator-only operational fields.
        public var hasOperationalDetails: Bool {
            database != nil || schemaMigrations != nil || uptimeSeconds != nil || replicaId != nil
        }

        /// First seven characters of the revision; nil for "unknown" and empty values.
        public var shortRevisionText: String? { SystemInfo.shortRevision(revisionShort ?? revision) }
    }

    public let backend: Backend

    public init(backend: Backend) { self.backend = backend }

    private enum CodingKeys: String, CodingKey { case backend }

    /// `abcdef0123` -> `abcdef0`; nil for missing and "unknown".
    public static func shortRevision(_ revision: String?) -> String? {
        guard let revision, !revision.isEmpty, revision != "unknown" else { return nil }
        return String(revision.prefix(7))
    }

    /// `2026-10-18T08:01:02Z` -> `2026-10-18`; nil for anything else.
    public static func shortDate(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        let day = String(iso.prefix(10))
        let parts = day.split(separator: "-")
        return parts.count == 3 && parts[0].count == 4 && parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) ? day : nil
    }

    /// `93784` -> `1 Tag 2 Std. 3 Min.`; seconds only below a minute.
    public static func formatUptime(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let days = total / 86400, hours = total % 86400 / 3600, minutes = total % 3600 / 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) \(days == 1 ? "Tag" : "Tage")") }
        if days > 0 || hours > 0 { parts.append("\(hours) Std.") }
        if days > 0 || hours > 0 || minutes > 0 { parts.append("\(minutes) Min.") }
        return parts.isEmpty ? "\(total) Sek." : parts.joined(separator: " ")
    }
}

/// Version of this app build (`CFBundleShortVersionString` and `CFBundleVersion`).
public struct AppBuildInfo: Sendable, Equatable {
    public let platform: String
    public let version: String
    public let build: String

    public init(platform: String, version: String, build: String) {
        self.platform = platform
        self.version = version
        self.build = build
    }

    /// Reads the bundle; unknown values show as "?".
    public init(platform: String, bundle: Bundle = .main) {
        let info = bundle.infoDictionary
        self.init(platform: platform, version: info?["CFBundleShortVersionString"] as? String ?? "?", build: info?["CFBundleVersion"] as? String ?? "?")
    }

    public var display: String { "\(version) (\(build))" }

    /// One line for bug reports, like the PWA: `Timetrack iOS 0.1.0 (8), Backend 0.1.0 (abc1234, 2026-10-18), API 0.23.0, mariadb`.
    /// Members' answers have no database field, so it is left out; without an answer the line says so (old backend).
    public func supportText(backend info: SystemInfo?) -> String {
        var text = "Timetrack \(platform) \(display)"
        guard let backend = info?.backend else { return text + ", Backend: keine Versionsangabe verfügbar" }
        var details: [String] = []
        if let revision = backend.shortRevisionText { details.append(revision) }
        if let date = SystemInfo.shortDate(backend.buildDate) { details.append(date) }
        text += ", Backend \(backend.version)" + (details.isEmpty ? "" : " (\(details.joined(separator: ", ")))")
        text += ", API \(backend.apiVersion)"
        if let database = backend.database { text += ", \(database)" }
        return text
    }
}

/// What the "Über Timetrack" section shows about the server.
public enum SystemInfoState: Sendable, Equatable {
    case idle
    case loading
    case loaded(SystemInfo)
    /// Old backend without the endpoint (404), no permission or unreachable: only the app version is shown.
    case unavailable

    public var info: SystemInfo? {
        if case .loaded(let info) = self { return info }
        return nil
    }
}
