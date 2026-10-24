import Foundation

public struct FixedBreak: Codable, Sendable, Hashable {
    /// `HH:mm` in the model's time zone.
    public var start: String
    public var end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }
}

public struct WorkModel: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let createdAt: Date?
    public let validFrom: LocalDay
    public let validTo: LocalDay?
    public let timezone: String?
    public let weeklyTargetSeconds: Int
    /// 1 = Monday ... 7 = Sunday.
    public let workdays: [Int]
    public let dailyTargetSeconds: [String: Int]?
    public let travelCountsAsWork: Bool?
    public let roundingEnabled: Bool?
    public let roundingMinutes: Int?
    public let fixedBreaks: [FixedBreak]?
    /// School time from which the day counts as fulfilled (seconds); nil on old servers (contract default 3 h).
    public let schoolFullDayThresholdSeconds: Int?
    /// Credit for such a school day; nil = the day's target.
    public let schoolCreditSeconds: Int?
    /// Minutes after midnight before which entries belong to the previous day.
    public let dayBoundaryMinutes: Int?
    /// Correction counter (contract v0.16.0, sent as `If-Match`); nil on older servers, which cannot correct versions.
    public let version: Int?

    public init(id: UUID, createdAt: Date? = nil, validFrom: LocalDay, validTo: LocalDay? = nil, timezone: String? = nil, weeklyTargetSeconds: Int,
                workdays: [Int], dailyTargetSeconds: [String: Int]? = nil, travelCountsAsWork: Bool? = nil, roundingEnabled: Bool? = nil,
                roundingMinutes: Int? = nil, fixedBreaks: [FixedBreak]? = nil, schoolFullDayThresholdSeconds: Int? = nil,
                schoolCreditSeconds: Int? = nil, dayBoundaryMinutes: Int? = nil, version: Int? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.validFrom = validFrom
        self.validTo = validTo
        self.timezone = timezone
        self.weeklyTargetSeconds = weeklyTargetSeconds
        self.workdays = workdays
        self.dailyTargetSeconds = dailyTargetSeconds
        self.travelCountsAsWork = travelCountsAsWork
        self.roundingEnabled = roundingEnabled
        self.roundingMinutes = roundingMinutes
        self.fixedBreaks = fixedBreaks
        self.schoolFullDayThresholdSeconds = schoolFullDayThresholdSeconds
        self.schoolCreditSeconds = schoolCreditSeconds
        self.dayBoundaryMinutes = dayBoundaryMinutes
        self.version = version
    }

    /// Zone used for local days; falls back to the contract default `Europe/Berlin`.
    public var timeZone: TimeZone {
        timezone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "Europe/Berlin") ?? .current
    }
}

extension Array where Element == WorkModel {
    /// The version in force today: the open-ended one, otherwise the latest.
    public func current() -> WorkModel? {
        sorted { $0.validFrom < $1.validFrom }.last { $0.validTo == nil } ?? sorted { $0.validFrom < $1.validFrom }.last
    }

    /// Corrections (`PUT /work-models/{id}`) need the version counter on every model (contract v0.16.0); older servers only create new versions.
    public var supportsCorrection: Bool { !isEmpty && allSatisfy { $0.version != nil } }
}

/// What a new version starting on a day does to the existing timeline (mirrors the server's `create` rules, WM2).
public enum NewVersionOutcome: Sendable, Equatable {
    /// Accepted. `endsPredecessor` is the version that is closed on `predecessorEnd` (the day before); nil when there is no open predecessor.
    case ok(endsPredecessor: WorkModel?, predecessorEnd: LocalDay?)
    /// The day is not after the newest version's start, or lies inside its closed range: the server answers 409 `model_overlap`.
    case overlaps(WorkModel)
}

/// Why a version cannot end on a day (mirrors the server's `endWorkModel`).
public enum EndVersionIssue: Sendable, Equatable {
    case invalidDate
    case beforeStart
    /// A later version starts on or before the end day.
    case overlapsLater(WorkModel)
}

extension Array where Element == WorkModel {
    /// Check of a new open-ended version starting on `validFrom`; the server still decides.
    public func checkNewVersion(validFrom: LocalDay) -> NewVersionOutcome {
        guard let newest = self.max(by: { $0.validFrom < $1.validFrom }) else { return .ok(endsPredecessor: nil, predecessorEnd: nil) }
        guard validFrom > newest.validFrom else { return .overlaps(newest) }
        if newest.validTo == nil { return .ok(endsPredecessor: newest, predecessorEnd: LocalDays.adding(-1, to: validFrom)) }
        if let end = newest.validTo, end >= validFrom { return .overlaps(newest) }
        return .ok(endsPredecessor: nil, predecessorEnd: nil)
    }

    /// Days without any work model between two consecutive versions (`from`...`to` inclusive), keyed by the version that follows the gap.
    public var gaps: [UUID: (from: LocalDay, to: LocalDay)] {
        let sorted = self.sorted { $0.validFrom < $1.validFrom }
        var result: [UUID: (from: LocalDay, to: LocalDay)] = [:]
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            guard let end = previous.validTo, let start = LocalDays.adding(1, to: end), let last = LocalDays.adding(-1, to: next.validFrom), start <= last else { continue }
            result[next.id] = (start, last)
        }
        return result
    }

    /// Versions that can still be ended: the open-ended ones.
    public var endable: [WorkModel] { filter { $0.validTo == nil } }

    public func checkEnd(of model: WorkModel, on day: LocalDay) -> EndVersionIssue? {
        guard LocalDays.parse(day) != nil else { return .invalidDate }
        guard day >= model.validFrom else { return .beforeStart }
        if let later = first(where: { $0.id != model.id && $0.validFrom > model.validFrom && $0.validFrom <= day }) { return .overlapsLater(later) }
        return nil
    }
}

/// Body of `PUT /work-models/{id}` and `POST /work-models/{id}/preview` (contract `WorkModelInput`).
public struct WorkModelInput: Encodable, Sendable, Equatable {
    public var validFrom: LocalDay
    /// nil = open-ended (sent as explicit `null`).
    public var validTo: LocalDay?
    public var timezone: String
    public var weeklyTargetSeconds: Int
    public var workdays: [Int]
    public var dailyTargetSeconds: [String: Int]?
    public var travelCountsAsWork: Bool
    public var roundingEnabled: Bool
    public var roundingMinutes: Int
    public var schoolFullDayThresholdSeconds: Int
    /// nil = the day's target (sent as explicit `null`).
    public var schoolCreditSeconds: Int?
    public var dayBoundaryMinutes: Int
    public var fixedBreaks: [FixedBreak]

    private enum CodingKeys: String, CodingKey {
        case validFrom, validTo, timezone, weeklyTargetSeconds, workdays, dailyTargetSeconds, travelCountsAsWork, roundingEnabled,
             roundingMinutes, schoolFullDayThresholdSeconds, schoolCreditSeconds, dayBoundaryMinutes, fixedBreaks
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(validFrom, forKey: .validFrom)
        try c.encode(validTo, forKey: .validTo)
        try c.encode(timezone, forKey: .timezone)
        try c.encode(weeklyTargetSeconds, forKey: .weeklyTargetSeconds)
        try c.encode(workdays, forKey: .workdays)
        try c.encodeIfPresent(dailyTargetSeconds, forKey: .dailyTargetSeconds)
        try c.encode(travelCountsAsWork, forKey: .travelCountsAsWork)
        try c.encode(roundingEnabled, forKey: .roundingEnabled)
        try c.encode(roundingMinutes, forKey: .roundingMinutes)
        try c.encode(schoolFullDayThresholdSeconds, forKey: .schoolFullDayThresholdSeconds)
        try c.encode(schoolCreditSeconds, forKey: .schoolCreditSeconds)
        try c.encode(dayBoundaryMinutes, forKey: .dayBoundaryMinutes)
        try c.encode(fixedBreaks, forKey: .fixedBreaks)
    }
}

/// `POST /work-models/{id}/preview`: the account balance up to today before and after the correction (nothing is saved).
public struct WorkModelPreview: Decodable, Sendable, Equatable {
    public let affectedFrom: LocalDay?
    public let affectedTo: LocalDay?
    public let affectedDays: Int
    public let balanceBeforeSeconds: Int
    public let balanceAfterSeconds: Int
    public let differenceSeconds: Int
    public let changedFields: [String]
    public let previousValidTo: LocalDay?

    public init(affectedFrom: LocalDay? = nil, affectedTo: LocalDay? = nil, affectedDays: Int, balanceBeforeSeconds: Int, balanceAfterSeconds: Int,
                differenceSeconds: Int, changedFields: [String] = [], previousValidTo: LocalDay? = nil) {
        self.affectedFrom = affectedFrom
        self.affectedTo = affectedTo
        self.affectedDays = affectedDays
        self.balanceBeforeSeconds = balanceBeforeSeconds
        self.balanceAfterSeconds = balanceAfterSeconds
        self.differenceSeconds = differenceSeconds
        self.changedFields = changedFields
        self.previousValidTo = previousValidTo
    }

    /// German names of the changed fields (unknown names are skipped), as in the PWA.
    public var changedFieldNames: [String] {
        changedFields.compactMap { Self.fieldNames[$0] }
    }

    static let fieldNames: [String: String] = [
        "validFrom": "Gültig ab", "validTo": "Gültig bis", "timezone": "Zeitzone", "weeklyTargetSeconds": "Wochen-Soll",
        "workdays": "Arbeitstage", "dailyTargetSeconds": "Tages-Soll", "travelCountsAsWork": "Fahrtzeiten", "roundingEnabled": "Rundung",
        "roundingMinutes": "Rundung in Minuten", "schoolFullDayThresholdSeconds": "Schulschwelle", "schoolCreditSeconds": "Schulgutschrift",
        "dayBoundaryMinutes": "Tagesgrenze", "fixedBreaks": "Feste Pausen",
    ]
}

/// Editable text values of a work model version (what the form fields hold) and their validation, mirroring the PWA's `work-model-form.ts`.
public struct WorkModelForm: Sendable, Equatable {
    public enum Field: Hashable, Sendable { case validFrom, validTo, timezone, weekly, workdays, roundingMinutes, schoolThreshold, schoolCredit, dayBoundary, fixedBreaks }

    public var validFrom: LocalDay
    /// Empty = open-ended.
    public var validTo: LocalDay
    public var timezone: String
    public var weeklyTarget: String
    public var workdays: Set<Int>
    public var travelCountsAsWork: Bool
    public var roundingEnabled: Bool
    public var roundingMinutes: String
    public var schoolThreshold: String
    public var schoolCredit: String
    public var dayBoundaryMinutes: String
    public var fixedBreaks: [FixedBreak]
    /// Per-weekday targets are not editable here; they are carried over unchanged so a correction does not drop them.
    public var dailyTargetSeconds: [String: Int]?

    public init(model: WorkModel) {
        validFrom = model.validFrom
        validTo = model.validTo ?? ""
        timezone = model.timezone ?? "Europe/Berlin"
        weeklyTarget = DurationFormat.hoursMinutes(model.weeklyTargetSeconds)
        workdays = Set(model.workdays)
        travelCountsAsWork = model.travelCountsAsWork ?? true
        roundingEnabled = model.roundingEnabled ?? true
        roundingMinutes = String(model.roundingMinutes ?? 15)
        schoolThreshold = DurationFormat.hoursMinutes(model.schoolFullDayThresholdSeconds ?? 10800)
        schoolCredit = model.schoolCreditSeconds.map(DurationFormat.hoursMinutes) ?? ""
        dayBoundaryMinutes = String(model.dayBoundaryMinutes ?? 0)
        fixedBreaks = model.fixedBreaks ?? []
        dailyTargetSeconds = (model.dailyTargetSeconds?.isEmpty ?? true) ? nil : model.dailyTargetSeconds
    }

    /// Form for a new version: values come from `base` (the newest version) and it starts on `validFrom`, open-ended (WM2).
    public init(basedOn base: WorkModel, startingOn validFrom: LocalDay) {
        self.init(model: base)
        self.validFrom = validFrom
        validTo = ""
    }

    /// Form for the very first version (no model yet), with the PWA's defaults.
    public init(validFrom: LocalDay, timezone: String = "Europe/Berlin") {
        self.validFrom = validFrom
        validTo = ""
        self.timezone = timezone
        weeklyTarget = "38:30"
        workdays = [1, 2, 3, 4, 5]
        travelCountsAsWork = true
        roundingEnabled = true
        roundingMinutes = "15"
        schoolThreshold = "3:00"
        schoolCredit = ""
        dayBoundaryMinutes = "0"
        fixedBreaks = []
        dailyTargetSeconds = nil
    }

    static func isValidDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m), (1...31).contains(d) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let date = calendar.date(from: DateComponents(year: y, month: m, day: d)) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == y && back.month == m && back.day == d
    }

    static func isValidTime(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }

    /// Validated request body, or the invalid fields. `validTo` is always part of a correction.
    public func build() -> Result<WorkModelInput, ValidationErrors> {
        var errors = Set<Field>()
        if !Self.isValidDay(validFrom) { errors.insert(.validFrom) }
        if !validTo.isEmpty {
            if !Self.isValidDay(validTo) || (Self.isValidDay(validFrom) && validTo < validFrom) { errors.insert(.validTo) }
        }
        let zone = timezone.trimmingCharacters(in: .whitespaces)
        if zone.isEmpty || TimeZone(identifier: zone) == nil { errors.insert(.timezone) }
        let weekly = DurationFormat.parse(weeklyTarget)
        if weekly == nil || weekly! < 0 || weekly! > 168 * 3600 { errors.insert(.weekly) }
        if workdays.isEmpty { errors.insert(.workdays) }
        let minutes = Int(roundingMinutes.trimmingCharacters(in: .whitespaces))
        if roundingEnabled, minutes == nil || !(1...60).contains(minutes!) { errors.insert(.roundingMinutes) }
        let threshold = DurationFormat.parse(schoolThreshold)
        if threshold == nil || threshold! < 0 { errors.insert(.schoolThreshold) }
        var credit: Int?
        if !schoolCredit.trimmingCharacters(in: .whitespaces).isEmpty {
            credit = DurationFormat.parse(schoolCredit)
            if credit == nil || credit! < 0 { errors.insert(.schoolCredit) }
        }
        let boundary = Int(dayBoundaryMinutes.trimmingCharacters(in: .whitespaces))
        if boundary == nil || !(0...719).contains(boundary!) { errors.insert(.dayBoundary) }
        if fixedBreaks.contains(where: { !Self.isValidTime($0.start) || !Self.isValidTime($0.end) || $0.start >= $0.end }) { errors.insert(.fixedBreaks) }
        guard errors.isEmpty, let weekly, let threshold, let boundary else { return .failure(ValidationErrors(fields: errors)) }
        return .success(WorkModelInput(
            validFrom: validFrom, validTo: validTo.isEmpty ? nil : validTo, timezone: zone, weeklyTargetSeconds: weekly, workdays: workdays.sorted(),
            dailyTargetSeconds: dailyTargetSeconds, travelCountsAsWork: travelCountsAsWork, roundingEnabled: roundingEnabled,
            roundingMinutes: roundingEnabled ? (minutes ?? 15) : (Int(roundingMinutes) ?? 15), schoolFullDayThresholdSeconds: threshold,
            schoolCreditSeconds: credit, dayBoundaryMinutes: boundary, fixedBreaks: fixedBreaks))
    }

    public struct ValidationErrors: Error, Sendable, Equatable { public let fields: Set<Field> }
}
