import Foundation

/// OT1: which overwork notifications the user wants. Each type is off by default; stored per device (the notifications are local).
public struct OverworkSettings: Codable, Sendable, Hashable {
    /// "Planned end reached": the end of the day from the plan.
    public var plannedEnd: Bool
    /// Warnings before and at the daily limits (8 h regular, 10 h maximum).
    public var dailyLimits: Bool
    /// Hint when the break needed after 6 h / 9 h of work has not been taken (actual times only).
    public var missingBreak: Bool

    public init(plannedEnd: Bool = false, dailyLimits: Bool = false, missingBreak: Bool = false) {
        self.plannedEnd = plannedEnd
        self.dailyLimits = dailyLimits
        self.missingBreak = missingBreak
    }

    public var isAnyEnabled: Bool { plannedEnd || dailyLimits || missingBreak }
}

/// Settings in the App Group so the app and the intents that pause or resume the timer read the same switches.
public struct OverworkSettingsStore: Sendable {
    private let suiteName: String?
    private static let key = "overwork.settings.v1"

    public init(suiteName: String? = WidgetSnapshot.appGroup) { self.suiteName = suiteName }

    private var defaults: UserDefaults? { suiteName.flatMap { UserDefaults(suiteName: $0) } }

    public func read() -> OverworkSettings {
        guard let data = defaults?.data(forKey: Self.key), let value = try? JSONDecoder().decode(OverworkSettings.self, from: data) else { return OverworkSettings() }
        return value
    }

    public func write(_ settings: OverworkSettings) {
        guard let defaults, let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Limits the notifications refer to. The backend only reports break hints (`breakHints`, ADR-0004, profile `arbzg-adult-de`) and exposes no daily
/// limit, so the daily limits are constants here. Hints only; no legal check.
public enum OverworkRules {
    /// Arbeitszeitgesetz section 3: eight hours a day regularly, up to ten hours with compensation.
    public static let regularLimitSeconds = 8 * 3600
    public static let maximumLimitSeconds = 10 * 3600
    /// How long before a limit the warning fires.
    public static let warningLeadSeconds = 30 * 60
    /// Arbeitszeitgesetz section 4 as the backend evaluates it (ADR-0004): more than 6 h of work needs 30 min of breaks in total, more than 9 h needs 45 min;
    /// a part shorter than 15 min does not count.
    public static let firstBreakAfterSeconds = 6 * 3600
    public static let firstBreakRequiredSeconds = 30 * 60
    public static let secondBreakAfterSeconds = 9 * 3600
    public static let secondBreakRequiredSeconds = 45 * 60
    public static let minimumBreakPartSeconds = 15 * 60
}

public enum OverworkKind: String, Sendable, Hashable, CaseIterable {
    case plannedEnd, regularLimitWarning, regularLimit, maximumLimitWarning, maximumLimit, breakAfter6, breakAfter9
}

/// One local notification to schedule.
public struct OverworkItem: Sendable, Hashable, Identifiable {
    public static let idPrefix = "de.linolaske.timetrack.overwork."

    /// Stable per kind (`prefix + kind`), so rescheduling replaces the pending request and a changed timer moves it.
    public let id: String
    public let kind: OverworkKind
    public let fireDate: Date
    public let title: String
    public let body: String
}

public enum OverworkPlanner {
    /// Which notifications must be pending for the timer state in `snapshot` at `now`.
    ///
    /// The work of the day at an instant `t` while the work timer runs is `todaySeconds + (t - startedAt)` (`todaySeconds` excludes the running
    /// segment, LA2), so every threshold has one fire instant; a pause, resume, stop or correction produces a new snapshot and with it new instants.
    /// Nothing is planned without a running work timer (the work does not grow), for another day than `now`, for instants that are already
    /// past (no immediate notification for a limit that is exceeded), or for instants after the end of the snapshot's local day (the day's totals reset).
    /// Durations are elapsed time and the planned end an absolute instant, so daylight-saving changes cannot shift them.
    public static func plan(snapshot: WidgetSnapshot, settings: OverworkSettings, now: Date) -> [OverworkItem] {
        guard settings.isAnyEnabled, snapshot.isRunning, snapshot.kind == .work, let started = snapshot.startedAt else { return [] }
        let zone = TimeZone(identifier: snapshot.timeZone) ?? .current
        let calendar = DayCalendar(timeZone: zone)
        guard snapshot.day == calendar.day(for: now), let dayEnd = calendar.interval(of: snapshot.day)?.end else { return [] }
        let done = max(0, snapshot.todaySeconds)

        func fire(atWorked seconds: Int) -> Date? {
            let date = started.addingTimeInterval(TimeInterval(seconds - done))
            return date > now && date < dayEnd ? date : nil
        }
        func clock(_ date: Date) -> String {
            let time = calendar.hourAndMinute(of: date)
            return String(format: "%d:%02d", time.hour, time.minute)
        }
        var items: [OverworkItem] = []
        func add(_ kind: OverworkKind, _ date: Date?, _ title: String, _ body: String) {
            guard let date else { return }
            items.append(OverworkItem(id: OverworkItem.idPrefix + kind.rawValue, kind: kind, fireDate: date, title: title, body: body))
        }

        if settings.plannedEnd, let end = snapshot.plannedEnd, end > now, end < dayEnd {
            add(.plannedEnd, end, "Geplantes Ende erreicht", "Laut Plan ist um \(clock(end)) Uhr Feierabend. Die Zeiterfassung läuft noch.")
        }
        if settings.dailyLimits {
            let lead = OverworkRules.warningLeadSeconds / 60
            add(.regularLimitWarning, fire(atWorked: OverworkRules.regularLimitSeconds - OverworkRules.warningLeadSeconds),
                "Gleich 8 Stunden", "In \(lead) Minuten sind heute 8 Stunden Arbeitszeit erreicht.")
            add(.regularLimit, fire(atWorked: OverworkRules.regularLimitSeconds),
                "8 Stunden erreicht", "Die reguläre Tagesgrenze von 8 Stunden ist erreicht. Bis 10 Stunden ist es mit Ausgleich möglich.")
            add(.maximumLimitWarning, fire(atWorked: OverworkRules.maximumLimitSeconds - OverworkRules.warningLeadSeconds),
                "Gleich 10 Stunden", "In \(lead) Minuten sind heute 10 Stunden Arbeitszeit erreicht.")
            add(.maximumLimit, fire(atWorked: OverworkRules.maximumLimitSeconds),
                "10 Stunden erreicht", "Die Höchstgrenze von 10 Stunden am Tag ist erreicht. Mehr ist nach dem Arbeitszeitgesetz nicht vorgesehen.")
        }
        if settings.missingBreak {
            // Only breaks that really happened count; nothing is assumed for the time still to come (the timer runs until the threshold).
            let taken = takenBreakSeconds(snapshot: snapshot, started: started)
            if taken < OverworkRules.firstBreakRequiredSeconds {
                add(.breakAfter6, fire(atWorked: OverworkRules.firstBreakAfterSeconds), "Pause noch offen",
                    "Nach 6 Stunden Arbeit sind 30 Minuten Pause vorgesehen. Bisher erfasst: \(breakText(taken)).")
            }
            if taken < OverworkRules.secondBreakRequiredSeconds {
                add(.breakAfter9, fire(atWorked: OverworkRules.secondBreakAfterSeconds), "Pause noch offen",
                    "Nach 9 Stunden Arbeit sind 45 Minuten Pause vorgesehen. Bisher erfasst: \(breakText(taken)).")
            }
        }
        return items.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }

    /// Sum of the gaps between today's segments that last at least the minimum break part. A gap before the first or after the last segment
    /// is no break, voided segments are not part of the snapshot.
    static func takenBreakSeconds(snapshot: WidgetSnapshot, started: Date) -> Int {
        var spans = (snapshot.segments ?? []).map { (start: $0.startedAt, end: $0.endedAt) }
        if !spans.contains(where: { $0.end == nil }) { spans.append((started, nil)) } // the running segment, should the list not contain it
        spans.sort { $0.start < $1.start }
        var total = 0
        var coveredUntil: Date?
        for span in spans {
            if let covered = coveredUntil {
                let gap = Int(span.start.timeIntervalSince(covered))
                if gap >= OverworkRules.minimumBreakPartSeconds { total += gap }
            }
            guard let end = span.end else { break }
            coveredUntil = max(coveredUntil ?? end, end)
        }
        return total
    }

    static func breakText(_ seconds: Int) -> String { seconds < 60 ? "keine" : "\(seconds / 60) Min" }

    /// Idempotent reconciliation against the identifiers currently pending: remove what is stale, (re)add everything planned.
    /// Foreign identifiers are never touched.
    public static func reconcile(pendingIDs: [String], planned: [OverworkItem]) -> (remove: [String], add: [OverworkItem]) {
        let wanted = Set(planned.map(\.id))
        return (pendingIDs.filter { $0.hasPrefix(OverworkItem.idPrefix) && !wanted.contains($0) }, planned)
    }
}
