import Foundation

/// The planned end and length of a day, taken from the plan day (`GET /plan/days`, contract 0.17.0). Planned is not worked:
/// this only labels the Live Activity ("Feierabend laut Plan") and never becomes a booked time.
public struct PlannedDay: Sendable, Equatable {
    /// Instant of the planned end on the plan day, in the work model's zone. Nil without planned times or on a day off.
    public var end: Date?
    /// Planned working seconds (`plannedSeconds`); computed from start, end and break when the server did not send it.
    public var seconds: Int?

    public init(end: Date? = nil, seconds: Int? = nil) {
        self.end = end
        self.seconds = seconds
    }

    public init(plan: PlanDay?, zone: TimeZone) {
        guard let plan, plan.mode != .off, let endText = plan.plannedEnd, let end = Self.instant(plan.date, endText, zone) else {
            self.init()
            return
        }
        var seconds = plan.plannedSeconds
        if seconds == nil, let startText = plan.plannedStart, let start = Self.instant(plan.date, startText, zone) {
            seconds = max(0, Int(end.timeIntervalSince(start)) - (plan.plannedBreakMinutes ?? 0) * 60)
        }
        self.init(end: end, seconds: seconds.flatMap { $0 > 0 ? $0 : nil })
    }

    /// `HH:mm` on a local day in `zone`; nil for malformed text.
    static func instant(_ day: LocalDay, _ clock: String, _ zone: TimeZone) -> Date? {
        let parts = clock.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return DayCalendar(timeZone: zone).instant(day: day, hour: hour, minute: minute)
    }
}
