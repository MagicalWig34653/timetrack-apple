import EventKit
import Foundation
import TimetrackCore
import TimetrackStores

/// EventKit-backed `DeviceCalendarProvider` (iOS/iPadOS). Reads only calendars the store asks for and writes only into the
/// dedicated "Timetrack" calendar; event data stays in this process and is never sent anywhere.
@MainActor
final class EventKitProvider: DeviceCalendarProvider {
    static let timetrackCalendarTitle = "Timetrack"

    private let store = EKEventStore()
    var onStoreChanged: (@MainActor () -> Void)?
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onStoreChanged?() }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .fullAccess: .full
        case .writeOnly: .writeOnly
        @unknown default: .denied
        }
    }

    func requestFullAccess() async throws -> CalendarAccess {
        _ = try await store.requestFullAccessToEvents()
        store.reset()
        return access
    }

    func calendars() -> [DeviceCalendarInfo] {
        store.calendars(for: .event)
            .map { DeviceCalendarInfo(id: $0.calendarIdentifier, title: $0.title, accountTitle: $0.source?.title ?? "", colorHex: Self.hex($0.cgColor), allowsWrite: $0.allowsContentModifications) }
            .sorted { ($0.accountTitle, $0.title) < ($1.accountTitle, $1.title) }
    }

    func events(from: Date, to: Date, calendarIDs: Set<String>) -> [DeviceEvent] {
        let selected = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: selected)
        return store.events(matching: predicate).map { event in
            let identifier = event.eventIdentifier ?? UUID().uuidString
            return DeviceEvent(id: "\(identifier)@\(Int(event.startDate.timeIntervalSince1970))", calendarID: event.calendar.calendarIdentifier,
                               title: event.title ?? "", location: event.location, start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                               isDeclined: Self.isDeclined(event), isCancelled: event.status == .canceled)
        }
    }

    // MARK: Writing

    func ensureTimetrackCalendar(existingID: String?) throws -> String {
        if let existingID, let existing = store.calendar(withIdentifier: existingID), existing.allowsContentModifications { return existing.calendarIdentifier }
        if let match = store.calendars(for: .event).first(where: { $0.title == Self.timetrackCalendarTitle && $0.allowsContentModifications }) { return match.calendarIdentifier }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.timetrackCalendarTitle
        let sources = store.sources
        guard let source = store.defaultCalendarForNewEvents?.source ?? sources.first(where: { $0.sourceType == .calDAV }) ?? sources.first(where: { $0.sourceType == .local }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar.calendarIdentifier
    }

    func writtenEvents(calendarID: String, from: Date, to: Date) -> [WrittenEvent] {
        guard let calendar = store.calendar(withIdentifier: calendarID) else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [calendar])
        return store.events(matching: predicate).compactMap { event in
            guard let day = PlanMarker.day(from: event.url), let id = event.eventIdentifier else { return nil }
            return WrittenEvent(eventID: id, day: day, title: event.title ?? "")
        }
    }

    func apply(_ operations: [WriteOperation], calendarID: String, calendar dayCalendar: DayCalendar) throws {
        guard let target = store.calendar(withIdentifier: calendarID), target.allowsContentModifications else { throw CocoaError(.fileWriteNoPermission) }
        do {
            for operation in operations {
                switch operation {
                case .create(let planned):
                    let event = EKEvent(eventStore: store)
                    event.calendar = target
                    try fill(event, with: planned, dayCalendar: dayCalendar)
                    try store.save(event, span: .thisEvent, commit: false)
                case .update(let id, let planned):
                    guard let event = store.event(withIdentifier: id), event.calendar.calendarIdentifier == calendarID, PlanMarker.day(from: event.url) != nil else { continue }
                    try fill(event, with: planned, dayCalendar: dayCalendar)
                    try store.save(event, span: .thisEvent, commit: false)
                case .delete(let id, _):
                    // Only events carrying Timetrack's marker inside the Timetrack calendar are ever removed.
                    guard let event = store.event(withIdentifier: id), event.calendar.calendarIdentifier == calendarID, PlanMarker.day(from: event.url) != nil else { continue }
                    try store.remove(event, span: .thisEvent, commit: false)
                }
            }
            try store.commit()
        } catch {
            store.reset()
            throw error
        }
    }

    private func fill(_ event: EKEvent, with planned: PlannedWorkEvent, dayCalendar: DayCalendar) throws {
        guard let interval = dayCalendar.interval(of: planned.day) else { throw CocoaError(.formatting) }
        event.title = planned.title
        event.isAllDay = true
        event.startDate = interval.start
        event.endDate = interval.start // all-day events end on their last day
        event.url = PlanMarker.url(for: planned.day)
        event.availability = .free
    }

    // MARK: Helpers

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    private static func hex(_ color: CGColor?) -> String? {
        guard let components = color?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components, components.count >= 3 else { return nil }
        return String(format: "%02X%02X%02X", Int((components[0] * 255).rounded()), Int((components[1] * 255).rounded()), Int((components[2] * 255).rounded()))
    }
}
