import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

/// Z2: month keys, page snapshots, the zoom state of the "Zeit" screen and the prefetch window of the calendar store.
@Suite struct MonthKeyTests {
    @Test func indexArithmeticCrossesYears() {
        let december = MonthKey(year: 2026, month: 12)
        #expect(december.adding(1) == MonthKey(year: 2027, month: 1))
        #expect(MonthKey(year: 2026, month: 1).adding(-1) == MonthKey(year: 2025, month: 12))
        #expect(MonthKey(year: 2026, month: 3).adding(-15) == MonthKey(year: 2024, month: 12))
        #expect(MonthKey(index: MonthKey(year: 2026, month: 10).index) == MonthKey(year: 2026, month: 10))
        #expect(MonthKey(day: "2026-10-16") == MonthKey(year: 2026, month: 10))
        #expect(MonthKey(day: "nope") == nil)
    }

    @Test func gridAlwaysHasSixMondayFirstRows() {
        for offset in -30...30 {
            let key = MonthKey(year: 2026, month: 10).adding(offset)
            let days = key.gridDays
            #expect(days.count == 42, "\(key)")
            #expect(LocalDays.isoWeekday(days[0]) == 1, "\(key)")
            #expect(days.contains(key.firstDay))
            #expect(days.prefix(7).contains { MonthKey(day: $0) == key } || MonthKey(day: days[7]) == key)
        }
        // October 2026 starts on a Thursday: the grid starts Monday 28 September and ends Sunday 8 November.
        let october = MonthKey(year: 2026, month: 10)
        #expect(october.gridRange.from == "2026-09-28")
        #expect(october.gridRange.to == "2026-11-08")
    }
}

@Suite struct MonthSnapshotTests {
    private func absence(_ kind: AbsenceKind, _ from: LocalDay, _ to: LocalDay) -> Absence {
        let json = #"{"id":"\#(UUID().uuidString)","version":1,"kind":"\#(kind.rawValue)","startDate":"\#(from)","endDate":"\#(to)","status":"planned","countedHalfDays":2}"#
        return try! JSONCoding.makeDecoder().decode(Absence.self, from: Data(json.utf8))
    }

    @Test func cellsCarryMarkersAndFlags() {
        let holiday = CalendarDay(startDate: "2026-10-31", endDate: "2026-10-31", name: "Reformationstag", kind: .holiday, source: .builtin)
        let plan = PlanDay(date: "2026-10-20", mode: .office, placeId: nil, note: nil)
        let snapshot = MonthSnapshot.build(key: MonthKey(year: 2026, month: 10), holidays: [holiday],
                                           absences: [absence(.vacation, "2026-10-19", "2026-10-21")], planDays: ["2026-10-20": plan])
        #expect(snapshot.cells.count == 42)
        #expect(snapshot.weekNumbers.count == 6)
        let tuesday = snapshot.cells.first { $0.day == "2026-10-20" }
        #expect(tuesday?.markers == [.absence(.vacation), .plan(.office)])
        #expect(tuesday?.inMonth == true)
        let holidayCell = snapshot.cells.first { $0.day == "2026-10-31" }
        #expect(holidayCell?.isHoliday == true && holidayCell?.isWeekend == true && holidayCell?.markers == [.holiday])
        #expect(snapshot.cells.first { $0.day == "2026-09-28" }?.inMonth == false)
        #expect(snapshot.cells.filter(\.inMonth).count == 31)
    }
}

@Suite struct TimeFocusTests {
    @Test func zoomKeepsTheAnchorDay() {
        var focus = TimeFocus(zoom: .month, day: "2026-10-22")
        focus.setZoom(.week)
        #expect(focus.weekStart == "2026-10-19" && focus.weekEnd == "2026-10-25")
        focus.shiftWeeks(2)
        #expect(focus.day == "2026-11-05")
        focus.setZoom(.month)
        #expect(focus.monthKey == MonthKey(year: 2026, month: 11))
    }

    @Test func planningIsOnlyAnEditingModeOfTheWeek() {
        var focus = TimeFocus(zoom: .week, day: "2026-10-22", isPlanning: true)
        #expect(focus.isPlanning)
        focus.setZoom(.month)
        #expect(!focus.isPlanning)
        focus.isPlanning = true
        #expect(!focus.isPlanning, "no planning in the month zoom")
        #expect(!TimeFocus(zoom: .month, day: "2026-10-22", isPlanning: true).isPlanning)
    }

    @Test func monthPagingPrefersTodayOtherwiseTheFirst() {
        var focus = TimeFocus(zoom: .month, day: "2026-10-22")
        focus.shiftMonths(1, today: "2026-10-22")
        #expect(focus.day == "2026-11-01")
        focus.shiftMonths(-1, today: "2026-10-22")
        #expect(focus.day == "2026-10-22")
    }
}

@MainActor
@Suite struct CalendarWindowTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let now = Date(timeIntervalSince1970: 1_792_130_820) // Fri 2026-10-16

    func store(_ transport: MockTransport, evaluationDay: LocalDay = "2026-10-16") -> CalendarStore {
        transport.enqueue("GET /api/v1/absences", body: "[]")
        transport.enqueue("GET /api/v1/plan/days", body: #"[{"date":"2026-10-20","mode":"office","placeId":null,"note":null}]"#)
        transport.enqueue("GET /api/v1/calendar/holidays", body: "[]")
        transport.enqueue("GET /api/v1/time/days", body: "[\(Fixtures.dayJSON.replacingOccurrences(of: "2026-10-16", with: evaluationDay))]")
        transport.enqueue("GET /api/v1/time/days/\(evaluationDay)", body: Fixtures.dayJSON.replacingOccurrences(of: "2026-10-16", with: evaluationDay))
        return CalendarStore(client: Fixtures.client(transport), calendar: calendar, now: now)
    }

    @Test func loadPrefetchesBothNeighbours() async {
        let transport = MockTransport()
        let store = store(transport)
        await store.load()
        await store.waitForPrefetch()
        let range = store.loadedRange
        #expect(range != nil)
        for offset in -1...1 {
            let grid = MonthKey(year: 2026, month: 10).adding(offset).gridRange
            #expect(range?.contains(grid.from) == true && range?.contains(grid.to) == true, "month offset \(offset) is loaded ahead")
        }
    }

    @Test func swipingToAPrefetchedMonthNeedsNoRequestAndNoWait() async {
        let transport = MockTransport()
        let store = store(transport)
        await store.load()
        await store.waitForPrefetch()
        let before = transport.requests(matching: "GET /api/v1/absences").count
        let hitsBefore = store.metrics.windowHits

        store.showMonth(MonthKey(year: 2026, month: 11)) // synchronous, as the pager does
        #expect(store.snapshot(for: store.visibleKey).cells.count == 42)
        #expect(store.planDays["2026-10-20"] != nil, "data stays in place, nothing is cleared while the page changes")
        await store.ensureWindow()
        #expect(transport.requests(matching: "GET /api/v1/absences").count == before, "served from the window")
        #expect(store.metrics.windowHits == hitsBefore + 1)
        #expect(store.metrics.windowMisses == 0)

        // The prefetch now extends the window by exactly the missing month on the far side.
        await store.waitForPrefetch()
        let december = MonthKey(year: 2026, month: 12).gridRange
        #expect(store.loadedRange?.contains(december.to) == true)
        let added = transport.requests(matching: "GET /api/v1/absences").dropFirst(before)
        #expect(added.count == 1, "one extension request, not a reload of three months")
    }

    @Test func aFarJumpStartsANewWindow() async {
        let transport = MockTransport()
        let store = store(transport)
        await store.load()
        await store.waitForPrefetch()
        await store.goTo(year: 2027, month: 6)
        #expect(store.metrics.windowMisses == 1)
        let june = MonthKey(year: 2027, month: 6).gridRange
        #expect(store.loadedRange?.contains(june.from) == true)
        #expect(store.loadedRange?.contains("2026-10-16") == false, "the old window is dropped, no hole in the middle")
    }

    @Test func snapshotsAreCachedPerDataVersion() async {
        let transport = MockTransport()
        let store = store(transport)
        await store.load()
        let key = store.visibleKey
        let first = store.snapshot(for: key)
        let builds = store.metrics.snapshotBuilds
        #expect(store.snapshot(for: key) == first)
        #expect(store.metrics.snapshotBuilds == builds, "reading a cached page builds nothing")
        transport.enqueue("PUT /api/v1/plan/days/2026-10-21", body: #"{"date":"2026-10-21","mode":"home","placeId":null,"note":null}"#)
        _ = await store.savePlan(day: "2026-10-21", PlanDayInput(mode: .home))
        #expect(store.snapshot(for: key) != first, "a change of the data rebuilds the page")
    }

    @Test func selectingADayAnswersFromTheWindow() async {
        let transport = MockTransport()
        let store = store(transport)
        await store.load()
        await store.select("2026-10-16")
        #expect(store.detail?.date == "2026-10-16", "the entries of the day are there without waiting for the network")
        #expect(store.detail?.segments?.isEmpty == false)
    }

    /// Measures how long the work around a month switch takes. The logged numbers go to the handoff; the bounds are loose (debug build, CI machine)
    /// but far below a frame budget multiple, so a regression into per-cell scans or reloads would show.
    @Test func monthSwitchTimingIsLoggedAndBounded() async {
        let transport = MockTransport()
        let store = store(transport)
        let clock = ContinuousClock()
        let loadStart = clock.now
        await store.load()
        let loadTime = clock.now - loadStart
        await store.waitForPrefetch()

        var worst = Duration.zero
        var total = Duration.zero
        for step in 1...12 {
            let start = clock.now
            store.showMonth(MonthKey(year: 2026, month: 10).adding(step))
            _ = store.snapshot(for: store.visibleKey)
            _ = store.snapshot(for: store.visibleKey.adding(1))
            _ = store.snapshot(for: store.visibleKey.adding(-1))
            let spent = clock.now - start
            total += spent
            worst = max(worst, spent)
            await store.ensureWindow()
            await store.waitForPrefetch()
        }
        let ms = { (d: Duration) in Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        print("Z2 timing: initial load \(String(format: "%.1f", ms(loadTime))) ms; synchronous work of a month switch avg \(String(format: "%.2f", ms(total) / 12)) ms, worst \(String(format: "%.2f", ms(worst))) ms; snapshot build last \(String(format: "%.3f", store.metrics.lastSnapshotSeconds * 1000)) ms; requests \(store.metrics.requests)")
        #expect(ms(worst) < 33, "the synchronous part of a switch stays within two frames (60 Hz)")
        #expect(store.metrics.windowMisses == 0, "paging month by month never waits for data")
    }
}

/// U2: pills and worked flag of the vertical month list.
@Suite struct MonthPillTests {
    private func absence(_ kind: AbsenceKind, _ status: String, _ day: LocalDay) -> Absence {
        let json = #"{"id":"\#(UUID().uuidString)","version":1,"kind":"\#(kind.rawValue)","startDate":"\#(day)","endDate":"\#(day)","status":"\#(status)","countedHalfDays":2}"#
        return try! JSONCoding.makeDecoder().decode(Absence.self, from: Data(json.utf8))
    }

    @Test func pillsFollowPriorityAndSkipOffPlans() {
        let holiday = CalendarDay(startDate: "2026-10-20", endDate: "2026-10-20", name: "Feiertag X", kind: .holiday, source: .builtin)
        let plan = PlanDay(date: "2026-10-20", mode: .office, placeId: nil, note: nil)
        let off = PlanDay(date: "2026-10-21", mode: .off, placeId: nil, note: nil)
        let snapshot = MonthSnapshot.build(key: MonthKey(year: 2026, month: 10), holidays: [holiday],
                                           absences: [absence(.vacation, "approved", "2026-10-20"), absence(.sick, "planned", "2026-10-20"), absence(.vacation, "planned", "2026-10-21")],
                                           planDays: ["2026-10-20": plan, "2026-10-21": off])
        let busy = snapshot.cells.first { $0.day == "2026-10-20" }!
        #expect(busy.pills.map(\.kind) == [.absence(.vacation), .absence(.sick), .holiday, .plan(.office)])
        #expect(busy.pills[0].tentative == false && busy.pills[1].tentative == true)
        #expect(busy.pills[2].text == "Feiertag X")
        let quiet = snapshot.cells.first { $0.day == "2026-10-21" }!
        #expect(quiet.pills.map(\.kind) == [.absence(.vacation)], "mode off is no pill")
        #expect(snapshot.cells.first { $0.day == "2026-10-22" }?.pills.isEmpty == true)
    }

    @Test func overflowTurnsTheLastSlotIntoACount() {
        let pills = (0..<4).map { _ in MonthPill(kind: .holiday, tentative: false, text: nil) }
        let two = MonthPill.visible(pills, capacity: 2)
        #expect(two.shown.count == 1 && two.hidden == 3, "one pill plus '+3'")
        let all = MonthPill.visible(Array(pills.prefix(2)), capacity: 2)
        #expect(all.shown.count == 2 && all.hidden == 0)
        #expect(MonthPill.visible(pills, capacity: 0).hidden == 4)
        #expect(MonthPill.visible([], capacity: 3).shown.isEmpty)
    }

    @Test func monthRowsCoverOnlyTheWeeksOfTheMonth() {
        // February 2027 starts on a Monday and has 28 days: exactly four rows.
        let february = MonthSnapshot.build(key: MonthKey(year: 2027, month: 2), holidays: [], absences: [], planDays: [:])
        #expect(february.monthRows.count == 4)
        #expect(february.monthRows.first?.cells.first?.day == "2027-02-01")
        // October 2026 spans five weeks (28 Sep to 1 Nov).
        let october = MonthSnapshot.build(key: MonthKey(year: 2026, month: 10), holidays: [], absences: [], planDays: [:])
        #expect(october.monthRows.count == 5)
        #expect(october.monthRows.map(\.week) == [40, 41, 42, 43, 44])
        // A 31-day month starting on a Sunday needs six rows.
        let may = MonthSnapshot.build(key: MonthKey(year: 2026, month: 3), holidays: [], absences: [], planDays: [:])
        #expect(may.monthRows.count == 6)
    }
}

/// U2: scroll geometry of the vertical month list.
@Suite struct MonthListLayoutTests {
    private let layout = MonthListLayout(first: MonthKey(year: 2026, month: 9), count: 6, rowHeight: 80, headerHeight: 40)

    @Test func sectionsStackWithTheirRowCounts() {
        // Sep 2026: Tue 1st, 30 days -> 5 rows; Oct: 5 rows; Nov (Sun 1st): 6 rows; Dec: 5; Jan 2027: Fri 1st, 31 days -> 5; Feb 2027: 4.
        #expect(MonthKey(year: 2026, month: 9).weekRows == 5)
        #expect(MonthKey(year: 2026, month: 3).weekRows == 6)
        #expect(MonthKey(year: 2027, month: 2).weekRows == 4)
        #expect(layout.offset(of: MonthKey(year: 2026, month: 9)) == 0)
        #expect(layout.offset(of: MonthKey(year: 2026, month: 10)) == 440)
        let rows: Double = 30
        #expect(layout.contentHeight == 240 + rows * 80)
    }

    @Test func offsetMapsToTheMonthUnderTheHeader() {
        let october = layout.offset(of: MonthKey(year: 2026, month: 10))
        #expect(layout.key(atOffset: 0) == MonthKey(year: 2026, month: 9))
        #expect(layout.key(atOffset: october - 0.5) == MonthKey(year: 2026, month: 9))
        #expect(layout.key(atOffset: october) == MonthKey(year: 2026, month: 10))
        #expect(layout.key(atOffset: -200) == MonthKey(year: 2026, month: 9), "rubber band above the list")
        #expect(layout.key(atOffset: 1_000_000) == MonthKey(year: 2027, month: 2), "rubber band below the list")
        // The probe lies below the header: a month whose header only just appeared at the bottom is not "the visible month" yet.
        #expect(layout.visibleKey(atOffset: october - 200) == MonthKey(year: 2026, month: 9))
        #expect(layout.visibleKey(atOffset: october - 30) == MonthKey(year: 2026, month: 10))
    }

    @Test func dayOffsetsPointAtTheWeekRow() {
        let october = layout.offset(of: MonthKey(year: 2026, month: 10))
        // Oct 2026: first row is the week of Mon 28 Sep (contains Thu 1 Oct), the next row starts Mon 5 Oct.
        #expect(layout.offset(of: "2026-10-01") == october + 40)
        #expect(layout.offset(of: "2026-10-05") == october + 120)
        #expect(layout.offset(of: "2026-10-29") == october + 360)
        #expect(layout.offset(of: "2030-01-01") == nil)
    }
}
