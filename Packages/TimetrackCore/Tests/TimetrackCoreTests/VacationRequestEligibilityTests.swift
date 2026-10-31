import Foundation
import Testing
@testable import TimetrackCore

// AUD3-B: which absences offer the vacation request PDF in the year overview and after the planner took a suggestion.

@Suite struct VacationRequestEligibilityTests {
    private func absence(_ kind: AbsenceKind, _ status: AbsenceStatus, _ from: String, _ to: String) -> Absence {
        Absence(id: UUID(), kind: kind, startDate: from, endDate: to, status: status, countedHalfDays: 2)
    }

    @Test func onlyLiveVacationIsEligible() {
        #expect(VacationRequestEligibility.isEligible(absence(.vacation, .planned, "2026-07-06", "2026-07-10")))
        #expect(VacationRequestEligibility.isEligible(absence(.vacation, .approved, "2026-07-06", "2026-07-10")))
        #expect(VacationRequestEligibility.isEligible(absence(.vacation, .taken, "2026-07-06", "2026-07-10")))
        #expect(!VacationRequestEligibility.isEligible(absence(.vacation, .cancelled, "2026-07-06", "2026-07-10")))
        #expect(!VacationRequestEligibility.isEligible(absence(.vacation, .rejected, "2026-07-06", "2026-07-10")))
        #expect(!VacationRequestEligibility.isEligible(absence(.sick, .planned, "2026-07-06", "2026-07-10")))
    }

    @Test func eligibleListIsSortedByStart() {
        let list = [absence(.vacation, .planned, "2026-09-01", "2026-09-04"), absence(.sick, .recorded, "2026-01-02", "2026-01-03"),
                    absence(.vacation, .requested, "2026-03-02", "2026-03-06"), absence(.vacation, .cancelled, "2026-02-02", "2026-02-03")]
        #expect(VacationRequestEligibility.eligible(in: list).map(\.startDate) == ["2026-03-02", "2026-09-01"])
    }
}
