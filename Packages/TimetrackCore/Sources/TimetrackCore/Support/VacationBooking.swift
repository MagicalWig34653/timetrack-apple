import Foundation

/// ADR-0034 (proposal): bookings on a vacation day are allowed everywhere and count like overtime; the day stays a vacation day.
/// Nothing here blocks anything. It only decides whether the optional note "Buchung an Urlaubstag" is shown. The same rule holds for
/// sick, excused and holiday days (the backend never blocked them); the note is only for vacation, as requested.
public enum VacationBooking {
    /// A vacation-marked day with recorded work (evaluated work seconds or at least one non-voided segment).
    public static func showsHint(mark: DayMarkKind?, workSeconds: Int, segmentCount: Int) -> Bool {
        mark == .vacation && (workSeconds > 0 || segmentCount > 0)
    }

    public static func showsHint(_ day: DayEvaluation) -> Bool {
        showsHint(mark: day.mark, workSeconds: day.evaluatedWorkSeconds, segmentCount: (day.segments ?? []).filter { !$0.voided }.count)
    }

    public static func showsHint(_ day: TimeWeekDay) -> Bool {
        showsHint(mark: day.mark == .vacation ? .vacation : nil, workSeconds: day.workSeconds, segmentCount: day.segmentsCount)
    }

    /// Plan/actual: on blocked days the server sends no `planActualDifferenceSeconds`; the booking is shown as actual time, not as a deviation.
    public static func actualSeconds(_ day: TimeWeekDay) -> Int { day.workSeconds + day.creditSeconds }
}
