import Foundation
import Testing
import TimetrackCore
import TimetrackStores

@Suite struct MonthRowRegressionTests {
    private func snapshot(_ key: MonthKey) -> MonthSnapshot {
        MonthSnapshot.build(key: key, holidays: [], absences: [], planDays: [:])
    }

    @Test func continuousListHasUniqueStableRowIdentities() {
        let first = MonthKey(year: 2025, month: 12)
        let snapshots = (0..<16).map { snapshot(first.adding($0)) }
        let rows = snapshots.flatMap(\.monthRows)
        // Lazy stacks flatten section children: a shared boundary week needs two identities.
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.map(\.id) == snapshots.flatMap { snapshot($0.key).monthRows }.map(\.id))
        let changed = MonthSnapshot.build(key: first, holidays: [CalendarDay(startDate: first.firstDay, endDate: first.firstDay,
            name: "Feiertag", kind: .holiday, source: .builtin)], absences: [], planDays: [:])
        #expect(changed.monthRows.map(\.id) == snapshots[0].monthRows.map(\.id))
    }

    @Test(arguments: [
        (2027, 2, 4, "2027-02-01", "2027-02-28"), // Monday, four weeks
        (2026, 10, 5, "2026-09-28", "2026-11-01"), // autumn DST
        (2026, 3, 6, "2026-02-23", "2026-04-05"), // Sunday, spring DST
        (2026, 11, 6, "2026-10-26", "2026-12-06"), // Sunday
        (2021, 1, 5, "2020-12-28", "2021-01-31") // ISO week 53
    ])
    func rowsCoverEveryDay(year: Int, month: Int, count: Int, start: String, end: String) {
        let key = MonthKey(year: year, month: month)
        let rows = snapshot(key).monthRows
        let days = rows.flatMap(\.cells).map(\.day)
        #expect(rows.count == count && key.weekRows == count)
        #expect(days.first == start && days.last == end)
        #expect(Set(days).count == count * 7)
        for row in rows {
            #expect(row.cells.count == 7)
            #expect(LocalDays.isoWeekday(row.cells[0].day) == 1)
            #expect(row.week == LocalDays.isoWeek(of: row.cells[0].day))
        }
        for (a, b) in zip(days, days.dropFirst()) { #expect(LocalDays.adding(1, to: a) == b) }
        let last = LocalDays.adding(-1, to: key.adding(1).firstDay)!
        #expect(rows.flatMap(\.cells).filter(\.inMonth).count == LocalDays.daysBetween(key.firstDay, last)! + 1)
        let layout = MonthListLayout(first: key, count: 2, rowHeight: 90, headerHeight: 44)
        #expect(layout.offset(of: key.adding(1)) == 44 + Double(count) * 90)
        for day in days where MonthKey(day: day) == key { #expect(layout.offset(of: day) != nil) }
    }

    @MainActor @Test(arguments: ["Europe/Berlin", "America/New_York"])
    func storeGridMatchesSnapshotAcrossDSTAndYearBoundary(zone: String) {
        let store = CalendarStore(client: Fixtures.client(MockTransport()), calendar: DayCalendar(timeZone: TimeZone(identifier: zone)!))
        for key in [MonthKey(year: 2026, month: 3), MonthKey(year: 2026, month: 10), MonthKey(year: 2021, month: 1), MonthKey(year: 2027, month: 2)] {
            store.showMonth(key)
            #expect(store.gridDays == snapshot(key).monthRows.flatMap(\.cells).map(\.day))
        }
    }
}
