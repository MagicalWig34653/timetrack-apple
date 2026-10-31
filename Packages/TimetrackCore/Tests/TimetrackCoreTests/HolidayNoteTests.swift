import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// AUD3-B: half company days (contract 0.32.0, ADR-0029) in the week planner and week list.

@Suite @MainActor struct HolidayNoteTests {
    private let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    private let now = ISO8601DateFormatter().date(from: "2026-12-16T10:00:00Z")!

    private static let planWeek = #"{"week":"2026-W52","from":"2026-12-21","to":"2026-12-27","days":[{"date":"2026-12-21","weekday":1,"targetSeconds":27720,"plannedSeconds":null,"blockedBy":null,"plan":null}],"totals":{"targetSeconds":27720,"plannedSeconds":0,"differenceSeconds":-27720}}"#

    private func day(_ date: String, _ name: String, _ treatment: CompanyDayTreatment?, end: String? = nil) -> CalendarDay {
        CalendarDay(startDate: date, endDate: end ?? date, name: name, kind: .holiday, source: .builtin, companyTreatment: treatment)
    }

    @Test func badgeAndHintDescribeHalfAndFullDays() {
        let half = HolidayNote(name: "Heiligabend", treatment: .half)
        #expect(half.isHalfDay && half.badge == "Heiligabend ½" && half.hint == "Heiligabend – halber Betriebstag, Soll halbiert")
        let full = HolidayNote(name: "Silvester", treatment: .full)
        #expect(!full.isHalfDay && full.badge == "Silvester" && full.hint == "Silvester – Betriebstag, wie ein Feiertag")
        let statutory = HolidayNote(name: "Neujahr", treatment: nil)
        #expect(!statutory.isHalfDay && statutory.badge == "Neujahr" && statutory.hint == "Neujahr")
    }

    @Test func notesCoverTheWeekAndPreferAFullHolidayOnTheSameDate() {
        let list = [day("2026-12-24", "Heiligabend", .half), day("2026-12-24", "Beispielfeiertag", nil),
                    day("2026-12-31", "Silvester", .half), day("2026-12-25", "1. Weihnachtstag", nil, end: "2026-12-26"),
                    CalendarDay(startDate: "2026-12-22", endDate: "2026-12-23", name: "Ferien", kind: .schoolHoliday, source: .builtin)]
        let notes = HolidayNote.notes(from: "2026-12-21", in: list)
        #expect(notes["2026-12-24"]?.name == "Beispielfeiertag" && notes["2026-12-24"]?.isHalfDay == false)
        #expect(notes["2026-12-26"]?.name == "1. Weihnachtstag")
        #expect(notes["2026-12-22"] == nil && notes["2026-12-31"] == nil) // school holidays and other weeks are not notes
        #expect(HolidayNote.notes(from: "2026-12-28", in: list)["2026-12-31"]?.isHalfDay == true)
    }

    @Test func weekListLabelKeepsTheHalfDaySuffixForOlderText() {
        #expect(CompanyDayText.title(name: "Heiligabend", treatment: .half) == "Heiligabend (halber Tag)")
    }

    @Test func plannerStoreLoadsHolidayNotesBestEffort() async {
        let planJSON = Self.planWeek
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/plan/weeks/2026-W52", body: planJSON)
        transport.enqueue("GET /api/v1/calendar/holidays", body: #"[{"startDate":"2026-12-24","endDate":"2026-12-24","name":"Heiligabend","kind":"holiday","source":"builtin","companyTreatment":"half"}]"#)
        let store = WeekPlanStore(client: Fixtures.client(transport), calendar: calendar, initialMonday: "2026-12-21", now: now)
        await store.load()
        #expect(store.holidayNotes["2026-12-24"]?.isHalfDay == true)
        let requested = transport.requests(matching: "GET /api/v1/calendar/holidays").compactMap { $0.url?.query }
        #expect(requested == ["year=2026"])
    }

    @Test func plannerStoreSurvivesAFailingHolidayRequest() async {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/plan/weeks/2026-W52", body: Self.planWeek)
        transport.enqueue("GET /api/v1/calendar/holidays", status: 500, body: "{}")
        let store = WeekPlanStore(client: Fixtures.client(transport), calendar: calendar, initialMonday: "2026-12-21", now: now)
        await store.load()
        #expect(store.week != nil && store.holidayNotes.isEmpty && store.error == nil)
    }
}
