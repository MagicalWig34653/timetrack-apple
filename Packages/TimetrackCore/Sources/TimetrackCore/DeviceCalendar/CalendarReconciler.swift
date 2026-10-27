import Foundation

// N2: reconciliation of the events Timetrack wrote with what the server says now (changed, moved, cancelled or deleted absences,
// removed plan days), with a local ledger "server item -> event identifier".

/// What the ledger remembers about one event Timetrack wrote into one calendar.
public struct CalendarLedgerRecord: Codable, Sendable, Equatable {
    public var eventID: String
    public var title: String
    public var firstDay: LocalDay
    public var lastDay: LocalDay
    /// P13: local start and end minute of a timed plan block event; nil for all-day events (older ledgers decode with nil).
    public var startMinute: Int?
    public var endMinute: Int?

    public init(eventID: String, title: String, firstDay: LocalDay, lastDay: LocalDay, startMinute: Int? = nil, endMinute: Int? = nil) {
        self.eventID = eventID
        self.title = title
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public init(eventID: String, entry: CalendarEntry) {
        self.init(eventID: eventID, title: entry.title, firstDay: entry.firstDay, lastDay: entry.lastDay, startMinute: entry.startMinute, endMinute: entry.endMinute)
    }

    /// Whether this record describes exactly what `entry` would write (so a missing event means the user removed it by hand).
    public func matches(_ entry: CalendarEntry) -> Bool {
        title == entry.title && firstDay == entry.firstDay && lastDay == entry.lastDay && startMinute == entry.startMinute && endMinute == entry.endMinute
    }
}

/// Per calendar: server item key (`absence/<uuid>`, `plan/<day>`, `plan/<day>/<n>` per plan block) -> record. Local to the device, never sent anywhere. The ledger is
/// an optimisation and a memory of manual deletions only: the marker on the events is the source of truth, so losing the ledger
/// (reinstall, new device, cleared defaults) is repaired by the next reconciliation.
public struct CalendarLedger: Codable, Sendable, Equatable {
    public var calendars: [String: [String: CalendarLedgerRecord]] = [:]

    public init(calendars: [String: [String: CalendarLedgerRecord]] = [:]) { self.calendars = calendars }

    public func records(for calendarID: String) -> [String: CalendarLedgerRecord] { calendars[calendarID] ?? [:] }

    public mutating func set(_ records: [String: CalendarLedgerRecord], for calendarID: String) {
        calendars[calendarID] = records.isEmpty ? nil : records
    }

    public mutating func clear(calendar calendarID: String) { calendars[calendarID] = nil }
}

/// The outcome of comparing wanted entries with the events found.
public struct CalendarReconciliation: Sendable, Equatable {
    public var operations: [WriteOperation] = []
    /// Keys whose record must be removed (event deleted because the item is gone, or a stale record of a vanished item).
    public var forget: Set<String> = []
    /// Keys whose existing event already matches but is not (correctly) in the ledger: the mapping is repaired from the event.
    public var adopt: [String: CalendarLedgerRecord] = [:]
    /// Keys the user removed by hand: not recreated while the item is unchanged.
    public var userRemoved: Set<String> = []
}

public enum CalendarReconciler {
    /// Compares `desired` (what the server says, within `[from, to]`) with the marker events `existing` and the ledger `records` of
    /// one calendar. Rules:
    /// - Only events with Timetrack's marker are ever updated or deleted (callers pass nothing else); a key family outside `managing`
    ///   and events outside the window are left alone.
    /// - Duplicates of one key are deleted; the one the ledger points to wins.
    /// - A wanted item without an event is created, unless the ledger shows the same content was written before and the event is
    ///   gone: then the user deleted it by hand and it stays gone until the item changes.
    /// - An event of an item that is no longer wanted (cancelled, rejected, deleted, other kind) is deleted.
    public static func plan(desired: [CalendarEntry], existing: [WrittenEvent], records: [String: CalendarLedgerRecord], from: LocalDay, to: LocalDay,
                            managing prefixes: [String] = [EntryMarker.planHost, EntryMarker.absenceHost]) -> CalendarReconciliation {
        func managed(_ key: String) -> Bool { prefixes.contains { key.hasPrefix($0 + "/") } }
        var result = CalendarReconciliation()
        var kept: [String: WrittenEvent] = [:]
        let inWindow = existing.filter { $0.lastDay >= from && $0.firstDay <= to && managed($0.key) }
        for event in inWindow.sorted(by: { ($0.firstDay, $0.eventID) < ($1.firstDay, $1.eventID) }) {
            if let current = kept[event.key] {
                // Duplicate: keep the one the ledger knows.
                if records[event.key]?.eventID == event.eventID {
                    result.operations.append(.delete(eventID: current.eventID))
                    kept[event.key] = event
                } else {
                    result.operations.append(.delete(eventID: event.eventID))
                }
            } else {
                kept[event.key] = event
            }
        }
        let wanted = Dictionary(desired.filter { managed($0.key) }.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        for key in wanted.keys.sorted() {
            guard let target = wanted[key] else { continue }
            if let current = kept[key] {
                if current.title != target.title || current.firstDay != target.firstDay || current.lastDay != target.lastDay
                    || current.startMinute != target.startMinute || current.endMinute != target.endMinute {
                    result.operations.append(.update(eventID: current.eventID, target))
                } else if records[key] != CalendarLedgerRecord(eventID: current.eventID, entry: target) {
                    result.adopt[key] = CalendarLedgerRecord(eventID: current.eventID, entry: target)
                }
            } else if let record = records[key], record.matches(target) {
                result.userRemoved.insert(key)
            } else {
                result.operations.append(.create(target))
            }
        }
        for (key, event) in kept where wanted[key] == nil {
            result.operations.append(.delete(eventID: event.eventID))
            result.forget.insert(key)
        }
        // A record of an item that is gone for good (inside the window, no event, no longer wanted) is dropped.
        for (key, record) in records where managed(key) && wanted[key] == nil && kept[key] == nil && record.lastDay >= from && record.firstDay <= to {
            result.forget.insert(key)
        }
        result.operations.sort { CalendarWritePlanner.sortKey($0) < CalendarWritePlanner.sortKey($1) }
        return result
    }
}
