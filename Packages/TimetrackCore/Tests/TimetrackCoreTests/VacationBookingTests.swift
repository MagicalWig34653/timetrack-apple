import Testing
import Foundation
@testable import TimetrackCore

/// VB1 / ADR-0034 (proposal): bookings on a vacation day are allowed; the day stays vacation, the booked time counts as overtime.
@Suite("VB1 bookings on vacation days")
struct VacationBookingTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    func segment(voided: Bool = false) -> Segment {
        Segment(id: UUID(), kind: .work, startedAt: base, endedAt: base.addingTimeInterval(3600), voided: voided)
    }

    func weekDay(mark: String, work: Int, count: Int, difference: String = "null") throws -> TimeWeekDay {
        let json = """
        {"date":"2026-11-03","weekday":2,"mark":"\(mark)","targetSeconds":0,"plannedSeconds":null,"planMode":null,"planActualDifferenceSeconds":\(difference),
         "workSeconds":\(work),"creditSeconds":0,"rawWorkSeconds":\(work),"breakSeconds":0,"breakDeductionSeconds":0,"travelSeconds":0,"schoolSeconds":0,
         "balanceSeconds":\(work),"firstStart":null,"lastEnd":null,"segmentsCount":\(count),"absences":[],"provisional":false,"isToday":false,"isFuture":false}
        """
        return try JSONCoding.makeDecoder().decode(TimeWeekDay.self, from: Data(json.utf8))
    }

    @Test func hintOnlyForVacationWithRecordedWork() {
        #expect(VacationBooking.showsHint(mark: .vacation, workSeconds: 3600, segmentCount: 1))
        #expect(VacationBooking.showsHint(mark: .vacation, workSeconds: 0, segmentCount: 1)) // running or not yet evaluated
        #expect(!VacationBooking.showsHint(mark: .vacation, workSeconds: 0, segmentCount: 0)) // plain vacation day
        #expect(!VacationBooking.showsHint(mark: .unmarked, workSeconds: 3600, segmentCount: 1))
        #expect(!VacationBooking.showsHint(mark: nil, workSeconds: 3600, segmentCount: 1))
        #expect(!VacationBooking.showsHint(mark: .sick, workSeconds: 3600, segmentCount: 1))
    }

    @Test func dayEvaluationIgnoresVoidedSegments() {
        let vacation = DayEvaluation(date: "2026-11-03", mark: .vacation, segments: [segment(voided: true)])
        #expect(!VacationBooking.showsHint(vacation))
        let booked = DayEvaluation(date: "2026-11-03", evaluatedWorkSeconds: 3600, mark: .vacation, segments: [segment()])
        #expect(VacationBooking.showsHint(booked))
        // Evaluated work without a segment list (older payloads) still counts.
        #expect(VacationBooking.showsHint(DayEvaluation(date: "2026-11-03", evaluatedWorkSeconds: 600, mark: .vacation)))
    }

    @Test func weekDayHintAndActualTime() throws {
        let booked = try weekDay(mark: "vacation", work: 7200, count: 1)
        #expect(VacationBooking.showsHint(booked))
        #expect(booked.planActualDifferenceSeconds == nil) // no plan on that day, so no deviation
        #expect(VacationBooking.actualSeconds(booked) == 7200)
        #expect(booked.hoursSeconds == 7200) // the actual time is not hidden by the vacation mark
        #expect(!VacationBooking.showsHint(try weekDay(mark: "vacation", work: 0, count: 0)))
        #expect(!VacationBooking.showsHint(try weekDay(mark: "holiday", work: 3600, count: 1)))
    }

    @Test func dayDeltaShowsSurplusOnVacationBooking() {
        // Vacation day: target 0, booked 2 h -> a positive difference (overtime), not hidden.
        let presentation = DayDeltaPolicy.presentation(day: "2026-11-03", today: "2026-11-05", doneSeconds: 7200, targetSeconds: 0, hasStarted: true)
        #expect(presentation == .surplus(7200))
    }

    @Test func weekOverviewIsNotEmptyWithVacationBooking() throws {
        #expect(!WeekOverview.isEmpty([try weekDay(mark: "vacation", work: 3600, count: 1)]))
    }
}
