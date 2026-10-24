import Foundation

// BH1: Berichtsheft (training report book), module `reports` (contract v0.27.0, ADR-0008).
// An entry = date + learning field (name snapshot) + duration + notes. Weeks are ISO weeks (Monday to Sunday).

/// `LearningField`: the account's own list; the app invents no content.
public struct LearningField: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var number: Int?
    public var name: String
    public var sortOrder: Int

    public init(id: UUID = UUID(), number: Int? = nil, name: String, sortOrder: Int = 0) {
        self.id = id
        self.number = number
        self.name = name
        self.sortOrder = sortOrder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decodeIfPresent(Int.self, forKey: .number)
        name = try c.decode(String.self, forKey: .name)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    /// "LF 4 · Name" for pickers; plain name without a number.
    public var displayName: String { number.map { "LF \($0) · \(name)" } ?? name }
}

public struct LearningFieldInput: Codable, Sendable, Hashable {
    public var number: Int?
    public var name: String
    public var sortOrder: Int

    public init(number: Int? = nil, name: String, sortOrder: Int = 0) {
        self.number = number
        self.name = name
        self.sortOrder = sortOrder
    }

    /// `number` is sent as an explicit `null` so a removed number is removed on the server too (PUT replaces).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let number { try c.encode(number, forKey: .number) } else { try c.encodeNil(forKey: .number) }
        try c.encode(name, forKey: .name)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

public struct ReportEntryInput: Codable, Sendable, Hashable {
    public var date: LocalDay
    public var learningFieldId: UUID?
    public var learningField: String
    public var durationSeconds: Int
    public var notes: String

    public init(date: LocalDay, learningFieldId: UUID? = nil, learningField: String, durationSeconds: Int = 0, notes: String = "") {
        self.date = date
        self.learningFieldId = learningFieldId
        self.learningField = learningField
        self.durationSeconds = durationSeconds
        self.notes = notes
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        if let learningFieldId { try c.encode(learningFieldId, forKey: .learningFieldId) } else { try c.encodeNil(forKey: .learningFieldId) }
        try c.encode(learningField, forKey: .learningField)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(notes, forKey: .notes)
    }
}

public struct ReportEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var version: Int
    public var date: LocalDay
    public var learningFieldId: UUID?
    public var learningField: String
    public var durationSeconds: Int
    public var notes: String
    public var createdAt: Date?
    /// True for AI-created drafts that are not confirmed yet (no backend endpoint creates them today; the flag is shown when set).
    public var draft: Bool

    public init(id: UUID = UUID(), version: Int = 1, date: LocalDay, learningFieldId: UUID? = nil, learningField: String,
                durationSeconds: Int = 0, notes: String = "", createdAt: Date? = nil, draft: Bool = false) {
        self.id = id
        self.version = version
        self.date = date
        self.learningFieldId = learningFieldId
        self.learningField = learningField
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.createdAt = createdAt
        self.draft = draft
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        date = try c.decode(String.self, forKey: .date)
        learningFieldId = try c.decodeIfPresent(UUID.self, forKey: .learningFieldId)
        learningField = try c.decode(String.self, forKey: .learningField)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        draft = try c.decodeIfPresent(Bool.self, forKey: .draft) ?? false
    }

    public var input: ReportEntryInput {
        ReportEntryInput(date: date, learningFieldId: learningFieldId, learningField: learningField, durationSeconds: durationSeconds, notes: notes)
    }
}

public enum ReportStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case draft, done
    /// Unknown future values read as a draft; the status is only a marker.
    public init(from decoder: Decoder) throws {
        self = ReportStatus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .draft
    }
}

public struct ReportFieldTotal: Codable, Sendable, Hashable, Identifiable {
    public let learningField: String
    public let seconds: Int
    public var id: String { learningField }

    public init(learningField: String, seconds: Int) {
        self.learningField = learningField
        self.seconds = seconds
    }
}

/// `GET /reports/weeks/{year}/{week}`: one ISO week with entries, sums and the tracked work time as a hint.
public struct ReportWeek: Codable, Sendable, Hashable {
    public var year: Int
    public var week: Int
    public var startDate: LocalDay
    public var endDate: LocalDay
    public var status: ReportStatus
    public var entries: [ReportEntry]
    public var totalSeconds: Int
    public var byLearningField: [ReportFieldTotal]
    public var trackedWorkSeconds: Int?
    public var sourceCount: Int

    public init(year: Int, week: Int, startDate: LocalDay, endDate: LocalDay, status: ReportStatus = .draft, entries: [ReportEntry] = [],
                totalSeconds: Int = 0, byLearningField: [ReportFieldTotal] = [], trackedWorkSeconds: Int? = nil, sourceCount: Int = 0) {
        self.year = year
        self.week = week
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.entries = entries
        self.totalSeconds = totalSeconds
        self.byLearningField = byLearningField
        self.trackedWorkSeconds = trackedWorkSeconds
        self.sourceCount = sourceCount
    }

    /// Entries of one day in capture order (the server order within a day).
    public func entries(on day: LocalDay) -> [ReportEntry] { entries.filter { $0.date == day } }
}

public struct ReportSourceInput: Codable, Sendable, Hashable {
    public var year: Int
    public var week: Int
    public var date: LocalDay?
    public var note: String?
    public var fileId: UUID?

    public init(year: Int, week: Int, date: LocalDay? = nil, note: String? = nil, fileId: UUID? = nil) {
        self.year = year
        self.week = week
        self.date = date
        self.note = note
        self.fileId = fileId
    }
}

/// A note or file the user collects as material for the week. Owner only, never shared.
public struct ReportSource: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var year: Int
    public var week: Int
    public var date: LocalDay?
    public var note: String?
    public var fileId: UUID?
    public var createdAt: Date?
    public var file: FileMeta?

    public init(id: UUID = UUID(), year: Int, week: Int, date: LocalDay? = nil, note: String? = nil, fileId: UUID? = nil, createdAt: Date? = nil, file: FileMeta? = nil) {
        self.id = id
        self.year = year
        self.week = week
        self.date = date
        self.note = note
        self.fileId = fileId
        self.createdAt = createdAt
        self.file = file
    }

    public var isFile: Bool { fileId != nil }
}

/// An ISO week as the report endpoints address it (`/reports/weeks/{year}/{week}`).
public struct ReportWeekRef: Sendable, Hashable, Codable {
    public var year: Int
    public var week: Int

    public init(year: Int, week: Int) {
        self.year = year
        self.week = week
    }

    /// The week that contains `day`; nil for malformed days.
    public init?(containing day: LocalDay) {
        guard let label = IsoWeek.label(containing: day), let ref = ReportWeekRef(label: label) else { return nil }
        self = ref
    }

    /// From `2026-W44`.
    public init?(label: String) {
        let parts = label.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), parts[1].hasPrefix("W"), let week = Int(parts[1].dropFirst()) else { return nil }
        self.year = year
        self.week = week
    }

    public var label: String { String(format: "%04d-W%02d", year, week) }
    public var monday: LocalDay { IsoWeek.monday(of: label) ?? "\(year)-01-01" }
    public var sunday: LocalDay { LocalDays.adding(6, to: monday) ?? monday }
    /// Monday to Sunday.
    public var days: [LocalDay] { (0..<7).compactMap { LocalDays.adding($0, to: monday) } }

    public func shifted(by weeks: Int) -> ReportWeekRef {
        LocalDays.adding(7 * weeks, to: monday).flatMap { ReportWeekRef(containing: $0) } ?? self
    }

    /// "KW 44/2026".
    public var title: String { "KW \(week)/\(year)" }
    public var weekCount: Int { Self.weeksIn(year) }

    /// 52 or 53: the week of 28 December is always the last one.
    public static func weeksIn(_ year: Int) -> Int {
        ReportWeekRef(containing: LocalDays.format(year: year, month: 12, day: 28))?.week ?? 52
    }

    /// Clamps to a week that exists (e.g. 53 in a 52-week year becomes 52).
    public static func valid(year: Int, week: Int) -> ReportWeekRef {
        ReportWeekRef(year: year, week: min(max(week, 1), weeksIn(year)))
    }
}
