import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// C3 (contract 0.36.0, ADR-0032): tolerant absence status, per-kind validity, time account without today.
@Suite struct AbsenceSemanticsTests {
    private func absenceJSON(kind: String, status: String?, id: String = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa") -> String {
        let statusPart = status.map { #""status":"\#($0)","# } ?? ""
        return #"{"id":"\#(id)","version":1,"kind":"\#(kind)","startDate":"2026-10-19","endDate":"2026-10-21",\#(statusPart)"countedHalfDays":6}"#
    }

    @Test func recordedUnknownAndMissingStatusDecode() throws {
        let decoder = JSONCoding.makeDecoder()
        let recorded = try decoder.decode(Absence.self, from: Data(absenceJSON(kind: "sick", status: "recorded").utf8))
        #expect(recorded.status == .recorded)
        let future = try decoder.decode(Absence.self, from: Data(absenceJSON(kind: "sick", status: "something_new").utf8))
        #expect(future.status == .unknown)
        let missing = try decoder.decode(Absence.self, from: Data(absenceJSON(kind: "other", status: nil).utf8))
        #expect(missing.status == .unknown)
    }

    @Test func weekAbsencesTolerateNewAndUnknownStatus() throws {
        let json = #"[{"kind":"sick","status":"recorded","halfDay":false},{"kind":"vacation","status":"zzz","halfDay":true},{"kind":"other","halfDay":false}]"#
        let list = try JSONCoding.makeDecoder().decode([TimeWeekAbsence].self, from: Data(json.utf8))
        #expect(list.map(\.status) == [.recorded, .unknown, .unknown])
    }

    @Test func listWithRecordedDoesNotBreak() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/absences", body: "[\(absenceJSON(kind: "sick", status: "recorded")),\(absenceJSON(kind: "vacation", status: "taken", id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))]")
        let list = try await Fixtures.client(transport).listAbsences(from: "2026-01-01", to: "2026-12-31")
        #expect(list.map(\.status) == [.recorded, .taken])
    }

    @Test func validityPerKind() {
        #expect(AbsenceStatus.valid(for: .vacation) == [.planned, .requested, .approved, .rejected, .cancelled, .taken])
        #expect(AbsenceStatus.valid(for: .sick) == [.recorded, .cancelled])
        #expect(AbsenceStatus.valid(for: .excused) == [.recorded, .cancelled])
        #expect(AbsenceStatus.valid(for: .other) == [.planned, .recorded, .cancelled])
        #expect(!AbsenceStatus.recorded.isValid(for: .vacation))
        #expect(!AbsenceStatus.approved.isValid(for: .sick))
        #expect(AbsenceStatus.serverDefault(for: .vacation) == .planned && AbsenceStatus.serverDefault(for: .sick) == .recorded)
        #expect(AbsenceStatus.approved.isApprovalFlow && !AbsenceStatus.recorded.isApprovalFlow && !AbsenceStatus.planned.isApprovalFlow)
    }

    @Test func sendableNeverSendsApprovalStatusForNonVacation() {
        #expect(AbsenceStatus.approved.sendable(for: .sick) == .recorded)
        #expect(AbsenceStatus.taken.sendable(for: .excused) == .recorded)
        #expect(AbsenceStatus.requested.sendable(for: .other) == .recorded)
        #expect(AbsenceStatus.planned.sendable(for: .other) == .planned)
        #expect(AbsenceStatus.cancelled.sendable(for: .sick) == .cancelled)
        #expect(AbsenceStatus.rejected.sendable(for: .sick) == nil)
        #expect(AbsenceStatus.recorded.sendable(for: .vacation) == nil)
        #expect(AbsenceStatus.unknown.sendable(for: .vacation) == nil)
        #expect(AbsenceStatus.approved.sendable(for: .vacation) == .approved)
    }

    @Test func inputOmitsStatusWhenNilAndForLegacyCopies() throws {
        func encoded(_ input: AbsenceInput) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(input)) as? [String: Any] ?? [:]
        }
        let none = AbsenceInput(kind: .sick, startDate: "2026-10-19", endDate: "2026-10-19", status: nil)
        #expect(try encoded(none)["status"] == nil)
        let legacy = try JSONCoding.makeDecoder().decode(Absence.self, from: Data(absenceJSON(kind: "sick", status: "approved").utf8))
        #expect(try encoded(AbsenceInput(legacy))["status"] as? String == "recorded")
        let unknown = try JSONCoding.makeDecoder().decode(Absence.self, from: Data(absenceJSON(kind: "vacation", status: "wow").utf8))
        #expect(try encoded(AbsenceInput(unknown))["status"] == nil)
        let vacation = AbsenceInput(kind: .vacation, startDate: "2026-10-19", endDate: "2026-10-19", status: .requested)
        #expect(try encoded(vacation)["status"] as? String == "requested")
    }

    @Test func calendarTitlesForRecorded() {
        #expect(AbsenceCalendarTitle.title(kind: .sick, status: .recorded) == "Krank")
        #expect(AbsenceCalendarTitle.title(kind: .other, status: .recorded) == nil)
        #expect(AbsenceCalendarTitle.title(kind: .sick, status: .cancelled) == nil)
    }

    @Test func listOptionsKnowRecorded() {
        #expect(AbsenceListOptions.statusChoices.contains(.recorded))
    }

    // MARK: Time account without today

    @Test func timeAccountDecodesTodayFields() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/time/account", body: #"{"asOf":"2026-10-29","accountStart":"2026-09-01","balanceSeconds":3600,"openingSeconds":0,"adjustmentSeconds":0,"provisional":false,"includesToday":false,"todayDeltaSeconds":2520}"#)
        let account = try await Fixtures.client(transport).getTimeAccount(asOf: "2026-10-29")
        #expect(account.includesToday == false && account.todayDeltaSeconds == 2520 && account.reportsTodaySeparately)
        // Older servers and a null delta keep working and show no separate line.
        let old = try JSONCoding.makeDecoder().decode(TimeAccount.self, from: Data(Fixtures.accountBalanceJSON.utf8))
        #expect(old.includesToday == nil && old.todayDeltaSeconds == nil && !old.reportsTodaySeparately)
        let nullDelta = try JSONCoding.makeDecoder().decode(TimeAccount.self, from: Data(#"{"asOf":"2026-10-20","accountStart":null,"balanceSeconds":0,"openingSeconds":0,"adjustmentSeconds":0,"provisional":false,"includesToday":false,"todayDeltaSeconds":null}"#.utf8))
        #expect(!nullDelta.reportsTodaySeparately)
    }

    @Test func statisticsDecodeTodayFields() throws {
        let json = #"""
        {"from":"2026-10-01","to":"2026-10-31","granularity":"week","basis":"evaluated","timezone":"Europe/Berlin","accountStart":null,"openingBalanceSeconds":null,
         "includesToday":false,"todayDeltaSeconds":-600,"buckets":[],
         "totals":{"targetSeconds":0,"targetToDateSeconds":0,"actualSeconds":0,"creditSeconds":0,"deltaSeconds":0,"overtimeSeconds":0,"undertimeSeconds":0,"breakSeconds":0,"breakDeductionSeconds":0,"kindSeconds":{"work":0,"school":0,"travel":0},"absenceDays":0}}
        """#
        let stats = try JSONCoding.makeDecoder().decode(TimeStatistics.self, from: Data(json.utf8))
        #expect(stats.includesToday == false && stats.todayDeltaSeconds == -600)
    }

    @Test func weekSummaryTodayFields() throws {
        let json = #"{"targetSeconds":1,"targetToDateSeconds":1,"workSeconds":1,"creditSeconds":0,"balanceSeconds":5,"includesToday":false,"todayDeltaSeconds":42,"plannedSeconds":null,"accountBalanceBeforeSeconds":0,"accountBalanceAfterSeconds":5,"accountBalanceAsOf":"2026-10-29","vacationDays":0,"sickDays":0,"schoolDays":0,"holidayDays":0,"workDays":1,"travelSeconds":0,"breakSeconds":0,"averageStart":null,"averageEnd":null,"longestDay":null,"provisional":false}"#
        let summary = try JSONCoding.makeDecoder().decode(TimeWeekSummary.self, from: Data(json.utf8))
        #expect(summary.separateTodayDeltaSeconds == 42)
        let old = try JSONCoding.makeDecoder().decode(TimeWeekSummary.self, from: Data(json.replacingOccurrences(of: #""includesToday":false,"todayDeltaSeconds":42,"#, with: "").utf8))
        #expect(old.separateTodayDeltaSeconds == nil)
    }
}
