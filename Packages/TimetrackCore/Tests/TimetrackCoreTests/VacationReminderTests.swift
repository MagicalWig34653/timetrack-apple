import Foundation
import Testing
@testable import TimetrackCore

@Suite struct VacationReminderTests {
    let berlin = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let newYork = DayCalendar(timeZone: TimeZone(identifier: "America/New_York")!)
    let idA = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    let idB = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!

    func absence(_ id: UUID, _ start: LocalDay, _ end: LocalDay, kind: AbsenceKind = .vacation, status: AbsenceStatus = .planned) -> Absence {
        Absence(id: id, kind: kind, startDate: start, endDate: end, status: status, countedHalfDays: 2)
    }

    func now(_ day: LocalDay, hour: Int = 8, in calendar: DayCalendar) -> Date { calendar.instant(day: day, hour: hour, minute: 0)! }

    func settings(_ lead: [Int] = [14, 3], hour: Int = 9, minute: Int = 0, enabled: Bool = true) -> VacationReminderSettings {
        VacationReminderSettings(enabled: enabled, leadDays: lead, hour: hour, minute: minute)
    }

    @Test func defaultsAreFourteenAndThreeDaysAtNineAndOff() {
        let value = VacationReminderSettings()
        #expect(value.enabled == false && value.leadDays == [14, 3] && value.hour == 9 && value.minute == 0)
    }

    @Test func plansTwoRemindersForPlannedVacation() {
        let items = VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-10", "2026-08-14")], settings: settings(),
                                                 now: now("2026-07-01", in: berlin), calendar: berlin)
        #expect(items.map(\.fireDay) == ["2026-07-27", "2026-08-07"])
        #expect(items.map(\.leadDays) == [14, 3])
        #expect(items.allSatisfy { berlin.hourAndMinute(of: $0.fireDate) == (9, 0) })
        #expect(items[0].id == "de.linolaske.timetrack.vacation-reminder.aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.14")
        #expect(items[0].body == "Urlaub vom 10. Aug. 2026 bis 14. Aug. 2026 noch nicht eingereicht. Er beginnt in 14 Tagen.")
        #expect(items[0].title == "Urlaub einreichen")
    }

    @Test func nothingWhenDisabledOrNotPlannedVacation() {
        let at = now("2026-07-01", in: berlin)
        let planned = absence(idA, "2026-08-10", "2026-08-14")
        #expect(VacationReminderPlanner.plan(absences: [planned], settings: settings(enabled: false), now: at, calendar: berlin).isEmpty)
        for status in [AbsenceStatus.requested, .approved, .rejected, .cancelled, .taken, .unknown] {
            #expect(VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-10", "2026-08-14", status: status)], settings: settings(), now: at, calendar: berlin).isEmpty)
        }
        for kind in [AbsenceKind.sick, .excused, .other, .unknown] {
            #expect(VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-10", "2026-08-14", kind: kind)], settings: settings(), now: at, calendar: berlin).isEmpty)
        }
    }

    @Test func dropsPastReminders() {
        // 5 days before the start: the 14-day reminder is gone, the 3-day one remains.
        let items = VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-10", "2026-08-14")], settings: settings(), now: now("2026-08-05", in: berlin), calendar: berlin)
        #expect(items.map(\.leadDays) == [3])
        // Exactly at the fire time nothing fires any more (strictly in the future only).
        let atFire = berlin.instant(day: "2026-08-07", hour: 9, minute: 0)!
        #expect(VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-10", "2026-08-14")], settings: settings([3]), now: atFire, calendar: berlin).isEmpty)
        // Vacation already started: nothing.
        #expect(VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-10", "2026-08-14")], settings: settings(), now: now("2026-08-10", in: berlin), calendar: berlin).isEmpty)
    }

    @Test func leadZeroFiresOnFirstDayAndMessageWording() {
        let items = VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-10", "2026-08-10")], settings: settings([0, 1]), now: now("2026-08-01", in: berlin), calendar: berlin)
        #expect(items.map(\.fireDay) == ["2026-08-09", "2026-08-10"])
        #expect(items[0].body == "Urlaub am 10. Aug. 2026 noch nicht eingereicht. Er beginnt morgen.")
        #expect(items[1].body == "Urlaub am 10. Aug. 2026 noch nicht eingereicht. Er beginnt heute.")
    }

    @Test func leadTimesAreNormalized() {
        let items = VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-20", "2026-08-21")], settings: settings([3, 3, -2, 7]), now: now("2026-08-01", in: berlin), calendar: berlin)
        #expect(items.map(\.leadDays) == [7, 3])
        #expect(settings([3, 3, -2, 7]).normalizedLeadDays == [7, 3])
    }

    @Test func idsAreStableAcrossRuns() {
        let list = [absence(idA, "2026-08-10", "2026-08-14"), absence(idB, "2026-09-10", "2026-09-14")]
        let first = VacationReminderPlanner.plan(absences: list, settings: settings(), now: now("2026-07-01", in: berlin), calendar: berlin)
        let second = VacationReminderPlanner.plan(absences: list.reversed(), settings: settings(), now: now("2026-07-02", in: berlin), calendar: berlin)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(Set(first.map(\.id)).count == 4)
        // Changed dates keep the id (the content is replaced on re-add).
        let moved = VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-17", "2026-08-21")], settings: settings(), now: now("2026-07-01", in: berlin), calendar: berlin)
        #expect(moved.map(\.id).sorted() == first.filter { $0.absenceID == idA }.map(\.id).sorted())
    }

    @Test func capsAtMaxItemsKeepingTheEarliest() {
        var list: [Absence] = []
        for i in 0..<30 { list.append(absence(UUID(), LocalDays.adding(30 + i * 5, to: "2026-01-01")!, LocalDays.adding(31 + i * 5, to: "2026-01-01")!)) }
        let items = VacationReminderPlanner.plan(absences: list, settings: settings(), now: now("2026-01-01", in: berlin), calendar: berlin)
        #expect(items.count == VacationReminderPlanner.maxItems)
        #expect(items == items.sorted { $0.fireDate < $1.fireDate })
        let all = VacationReminderPlanner.plan(absences: list, settings: settings(), now: now("2026-01-01", in: berlin), calendar: berlin)
        #expect(all.last!.fireDate <= items.last!.fireDate)
    }

    @Test func reconcileRemovesStaleOwnItemsOnly() {
        let planned = VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-10", "2026-08-14")], settings: settings(), now: now("2026-07-01", in: berlin), calendar: berlin)
        let stale = "\(VacationReminderItem.idPrefix)\(idB.uuidString.lowercased()).3"
        let result = VacationReminderPlanner.reconcile(pendingIDs: [planned[0].id, stale, "de.linolaske.timetrack.focus.start"], planned: planned)
        #expect(result.remove == [stale])
        #expect(result.add == planned)
        // Everything gone (deleted/submitted): all own items are removed, foreign ones stay.
        let cleared = VacationReminderPlanner.reconcile(pendingIDs: [planned[0].id, planned[1].id, "other"], planned: [])
        #expect(cleared.remove == [planned[0].id, planned[1].id] && cleared.add.isEmpty)
        // Idempotent: a second pass with the same pending set removes nothing.
        let again = VacationReminderPlanner.reconcile(pendingIDs: planned.map(\.id), planned: planned)
        #expect(again.remove.isEmpty)
    }

    // MARK: Time zones and daylight saving

    @Test func springForwardGapMovesToNextValidMinuteOnTheSameDay() {
        // 2026-03-29 02:30 does not exist in Berlin (02:00 -> 03:00).
        let items = VacationReminderPlanner.plan(absences: [absence(idA, "2026-04-01", "2026-04-03")], settings: settings([3], hour: 2, minute: 30), now: now("2026-03-01", in: berlin), calendar: berlin)
        #expect(items.count == 1)
        #expect(berlin.day(for: items[0].fireDate) == "2026-03-29")
        let time = berlin.hourAndMinute(of: items[0].fireDate)
        #expect(time.hour == 3)
    }

    @Test func fallBackOverlapFiresOnceOnTheRightDay() {
        // 2026-10-25 02:30 happens twice in Berlin; exactly one reminder with the first occurrence.
        let items = VacationReminderPlanner.plan(absences: [absence(idA, "2026-10-28", "2026-10-30")], settings: settings([3], hour: 2, minute: 30), now: now("2026-10-01", in: berlin), calendar: berlin)
        #expect(items.count == 1)
        #expect(berlin.day(for: items[0].fireDate) == "2026-10-25")
        #expect(berlin.hourAndMinute(of: items[0].fireDate) == (2, 30))
    }

    @Test func wallClockStaysAcrossDstChange() {
        // Scheduling in winter for a summer date: still 09:00 local (08:00 UTC in CEST, not 08:00 CET shifted).
        let items = VacationReminderPlanner.plan(absences: [absence(idA, "2026-04-06", "2026-04-10")], settings: settings([14, 3]), now: now("2026-01-15", in: berlin), calendar: berlin)
        #expect(items.map(\.fireDay) == ["2026-03-23", "2026-04-03"])
        #expect(items.allSatisfy { berlin.hourAndMinute(of: $0.fireDate) == (9, 0) })
        // 03-23 is still CET (UTC+1), 04-03 is CEST (UTC+2).
        #expect(items[0].fireDate == ISO8601DateFormatter().date(from: "2026-03-23T08:00:00Z"))
        #expect(items[1].fireDate == ISO8601DateFormatter().date(from: "2026-04-03T07:00:00Z"))
    }

    @Test func fireInstantFollowsTheWorkModelTimeZoneNotTheDevice() {
        let a = VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-10", "2026-08-14")], settings: settings([3]), now: now("2026-07-01", in: berlin), calendar: berlin)
        let b = VacationReminderPlanner.plan(absences: [absence(idA, "2026-08-10", "2026-08-14")], settings: settings([3]), now: now("2026-07-01", in: berlin), calendar: newYork)
        #expect(a[0].fireDay == b[0].fireDay)
        #expect(b[0].fireDate.timeIntervalSince(a[0].fireDate) == 6 * 3600)
        #expect(b[0].timeZoneIdentifier == "America/New_York")
    }

    @Test func leadAcrossMonthAndYearBoundary() {
        let items = VacationReminderPlanner.plan(absences: [absence(idA, "2027-01-04", "2027-01-15")], settings: settings([14, 3]), now: now("2026-12-01", in: berlin), calendar: berlin)
        #expect(items.map(\.fireDay) == ["2026-12-21", "2027-01-01"])
    }

    @Test func dateTextFormatting() {
        #expect(VacationReminderText.day("2026-03-05") == "5. März 2026")
        #expect(VacationReminderText.day("bogus") == "bogus")
        #expect(VacationReminderText.lead(1) == "1 Tag" && VacationReminderText.lead(3) == "3 Tage")
        #expect(VacationReminderText.lead(7) == "1 Woche" && VacationReminderText.lead(14) == "2 Wochen")
    }
}
