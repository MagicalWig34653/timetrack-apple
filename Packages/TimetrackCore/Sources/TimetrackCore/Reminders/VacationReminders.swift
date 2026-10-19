import Foundation

/// User settings of the "submit your vacation" reminders (R3). Stored on this device only (the notifications are local).
public struct VacationReminderSettings: Codable, Sendable, Hashable {
    public var enabled: Bool
    /// Days before the first vacation day at which a reminder fires (0 = on the first day). Distinct, non-negative.
    public var leadDays: [Int]
    public var hour: Int
    public var minute: Int

    public static let defaultLeadDays = [14, 3]
    /// Selectable lead times of the settings page.
    public static let leadDayChoices = [1, 2, 3, 5, 7, 14, 21, 28]

    public init(enabled: Bool = false, leadDays: [Int] = VacationReminderSettings.defaultLeadDays, hour: Int = 9, minute: Int = 0) {
        self.enabled = enabled
        self.leadDays = leadDays
        self.hour = hour
        self.minute = minute
    }

    /// Lead times cleaned for planning: non-negative, distinct, largest first.
    public var normalizedLeadDays: [Int] { Array(Set(leadDays.filter { $0 >= 0 })).sorted(by: >) }
}

/// One local notification to schedule.
public struct VacationReminderItem: Sendable, Hashable, Identifiable {
    public static let idPrefix = "de.linolaske.timetrack.vacation-reminder."

    /// Stable: `prefix + absence id + "." + lead days`. The same absence and lead time always yield the same identifier.
    public let id: String
    public let absenceID: UUID
    public let leadDays: Int
    public let startDate: LocalDay
    public let endDate: LocalDay
    /// Wall-clock fire time on `fireDay` in the time zone `timeZoneIdentifier`.
    public let fireDay: LocalDay
    public let hour: Int
    public let minute: Int
    public let timeZoneIdentifier: String
    public let fireDate: Date
    public let title: String
    public let body: String
}

public enum VacationReminderPlanner {
    /// iOS keeps at most 64 pending local notifications per app; stay below it so other features keep room.
    public static let maxItems = 40

    /// Pure planning: which notifications must exist for `absences` at `now`.
    /// Only vacation with status `planned` (not yet submitted) is reminded; everything else yields nothing. Items in the past are dropped;
    /// the earliest `maxItems` are kept. Fire times are wall-clock times in `calendar`'s time zone, so a daylight-saving change
    /// between scheduling and firing does not shift them (a time that does not exist on the spring-forward day moves to the next valid minute).
    public static func plan(absences: [Absence], settings: VacationReminderSettings, now: Date, calendar: DayCalendar) -> [VacationReminderItem] {
        guard settings.enabled else { return [] }
        let hour = min(max(settings.hour, 0), 23)
        let minute = min(max(settings.minute, 0), 59)
        var items: [VacationReminderItem] = []
        for absence in absences where absence.kind == .vacation && absence.status == .planned {
            guard LocalDays.parse(absence.startDate) != nil, LocalDays.parse(absence.endDate) != nil else { continue }
            for lead in settings.normalizedLeadDays {
                guard let fireDay = LocalDays.adding(-lead, to: absence.startDate),
                      let fire = calendar.instant(day: fireDay, hour: hour, minute: minute), fire > now else { continue }
                items.append(VacationReminderItem(
                    id: "\(VacationReminderItem.idPrefix)\(absence.id.uuidString.lowercased()).\(lead)",
                    absenceID: absence.id, leadDays: lead, startDate: absence.startDate, endDate: absence.endDate,
                    fireDay: fireDay, hour: hour, minute: minute, timeZoneIdentifier: calendar.timeZone.identifier, fireDate: fire,
                    title: "Urlaub einreichen", body: VacationReminderText.body(start: absence.startDate, end: absence.endDate, leadDays: lead)))
            }
        }
        items.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(items.prefix(maxItems))
    }

    /// Idempotent reconciliation against the identifiers currently pending: remove what is stale, (re)add everything planned.
    /// Adding an existing identifier replaces it, so unchanged items are harmless; foreign identifiers are never touched.
    public static func reconcile(pendingIDs: [String], planned: [VacationReminderItem]) -> (remove: [String], add: [VacationReminderItem]) {
        let wanted = Set(planned.map(\.id))
        let stale = pendingIDs.filter { $0.hasPrefix(VacationReminderItem.idPrefix) && !wanted.contains($0) }
        return (stale, planned)
    }
}

public enum VacationReminderText {
    private static let months = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]

    /// "3. Aug. 2026"; locale independent so tests and notifications agree.
    public static func day(_ day: LocalDay) -> String {
        guard let p = LocalDays.parse(day) else { return day }
        return "\(p.day). \(months[p.month - 1]) \(p.year)"
    }

    public static func body(start: LocalDay, end: LocalDay, leadDays: Int) -> String {
        let range = start == end ? "Urlaub am \(day(start))" : "Urlaub vom \(day(start)) bis \(day(end))"
        let when: String
        switch leadDays {
        case 0: when = " Er beginnt heute."
        case 1: when = " Er beginnt morgen."
        default: when = " Er beginnt in \(leadDays) Tagen."
        }
        return "\(range) noch nicht eingereicht.\(when)"
    }

    /// Display name of a lead time in the settings page ("1 Tag", "2 Wochen").
    public static func lead(_ days: Int) -> String {
        if days == 1 { return "1 Tag" }
        if days >= 7, days % 7 == 0 { return days == 7 ? "1 Woche" : "\(days / 7) Wochen" }
        return "\(days) Tage"
    }
}
