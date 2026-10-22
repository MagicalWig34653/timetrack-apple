import XCTest

/// Z2: the one "Zeit" screen against the throwaway backend (skipped without TT_DEV_SERVER): month zoom with day details including the
/// recorded entries, week zoom with the balance, switching between them, and paging between months by swipe.
/// Screenshots go to TT_SHOT_DIR (prefix TT_SHOT_PREFIX, default "z2"); TT_SHOT_SCHEME (light|dark) overrides the appearance.
final class TimeCalendarTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "z2"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch(zoom: String) throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "z2"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-time.zoom", zoom]
        if let scheme = env["TT_SHOT_SCHEME"] { app.launchArguments += ["-appearance.scheme", scheme] }
        app.launch()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
    }

    private func open(_ title: String, _ id: String) {
        let tab = app.tabBars.buttons[title]
        if tab.exists { tab.tap() } else { el("sidebar.\(id)").tap() }
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }

    private func waitForTitleChange(from title: String) {
        for _ in 0..<10 where el("calendar.title").label == title { sleep(1) }
    }

    /// Week zoom: one list (no Liste/Woche/Planen segments, no extra screens), the balance unfolds in the header.
    func testWeekZoom() throws {
        try launch(zoom: "week")
        open("Zeit", "time")
        XCTAssertTrue(el("time.week_details").waitForExistence(timeout: 15))
        XCTAssertTrue(app.segmentedControls["time.zoom"].exists || el("time.zoom").exists, "month and week are one switch of one screen")
        sleep(1)
        shot("week")
        el("time.week_details").tap()
        XCTAssertTrue(el("week.summary").waitForExistence(timeout: 15))
        sleep(1)
        shot("week-balance")
    }

    /// Month zoom: the grid, the selected day's details below (entries, plan, absences, actions) without a sheet; swipe pages the months.
    func testMonthZoom() throws {
        try launch(zoom: "month")
        open("Zeit", "time")
        XCTAssertTrue(el("calendar.title").waitForExistence(timeout: 10))
        XCTAssertTrue(el("day.vacation").waitForExistence(timeout: 10), "details of the selected day show without opening a sheet")
        XCTAssertTrue(el("day.entries").exists || el("day.entries.empty").exists, "the recorded entries of the day are part of the details")
        sleep(1)
        shot("month")
        let before = el("calendar.title").label
        app.buttons["calendar.next"].tap()
        waitForTitleChange(from: before)
        XCTAssertNotEqual(el("calendar.title").label, before)
        shot("month-next")

        // Swipe back over the grid (the pager follows the finger and settles on the previous month).
        let afterNext = el("calendar.title").label
        let grid = el("day.\(firstOfVisibleMonthGuess())").exists ? el("day.\(firstOfVisibleMonthGuess())") : app.scrollViews.firstMatch
        grid.swipeRight()
        waitForTitleChange(from: afterNext)
        XCTAssertEqual(el("calendar.title").label, before, "one swipe, one month")

        // Seeded approved vacation starts three weeks after this week's Monday (visible in the following month for most weeks).
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let monday = cal.dateInterval(of: .weekOfYear, for: Date())!.start
        let vacationDay = cal.date(byAdding: .day, value: 21, to: monday)!
        let target = el("day.\(dayString(vacationDay))")
        if !target.exists { app.buttons["calendar.next"].tap(); sleep(1) }
        if target.waitForExistence(timeout: 3) {
            target.tap()
            sleep(1)
            shot("month-vacation-day")
        }
        el("time.today").tap()
        for _ in 0..<10 where el("calendar.title").label != before { sleep(1) }
        XCTAssertEqual(el("calendar.title").label, before)

        // Zoom to the week of the selected day and back: same anchor, one screen.
        app.segmentedControls["time.zoom"].buttons["Woche"].tap()
        XCTAssertTrue(el("time.week_details").waitForExistence(timeout: 10))
        sleep(1)
        shot("zoom-week")
        app.segmentedControls["time.zoom"].buttons["Monat"].tap()
        XCTAssertTrue(el("calendar.title").waitForExistence(timeout: 10))
        XCTAssertEqual(el("calendar.title").label, before)
    }

    private func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "Europe/Berlin"); f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// Any day of the visible month: the 15th of the month shown by the title is not known to the test, so use today's month plus one (after "next").
    private func firstOfVisibleMonthGuess() -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let next = cal.date(byAdding: .month, value: 1, to: Date())!
        let c = cal.dateComponents([.year, .month], from: next)
        return String(format: "%04d-%02d-15", c.year!, c.month!)
    }

    /// Frame-time approximation while paging through months (Z2 measurement; numbers are in the handoff). A display link inside the Debug
    /// build counts frames and long frame intervals (`TT_DEV_FRAMEMETER`). TT_PERF_BASELINE=1 opens the old "Kalender" tab of the build
    /// before Z2 instead of the month zoom, for the before/after comparison.
    func testMonthSwipeFrames() throws {
        let baseline = ProcessInfo.processInfo.environment["TT_PERF_BASELINE"] != nil
        let env = ProcessInfo.processInfo.environment
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = try XCTUnwrap(env["TT_DEV_SERVER"])
        app.launchEnvironment["TT_DEV_COOKIE"] = try XCTUnwrap(env["TT_DEV_COOKIE"])
        app.launchEnvironment["TT_DEV_FRAMEMETER"] = "1"
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-time.zoom", "month"]
        app.launch()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
        if baseline { open("Kalender", "calendar") } else { open("Zeit", "time") }
        XCTAssertTrue(el("calendar.title").waitForExistence(timeout: 15))
        sleep(3)
        let meter = el("framemeter")
        XCTAssertTrue(meter.exists)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.34))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.34))
        var report: [String] = []
        for (name, velocity) in [("slow", XCUIGestureVelocity.slow), ("fast", .fast)] {
            meter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() // reset the counters
            let startTitle = el("calendar.title").label
            for _ in 0..<4 { from.press(forDuration: 0.02, thenDragTo: to, withVelocity: velocity, thenHoldForDuration: 0) }
            for _ in 0..<4 { to.press(forDuration: 0.02, thenDragTo: from, withVelocity: velocity, thenHoldForDuration: 0) }
            sleep(2)
            report.append("\(name): \(meter.label) (title \(startTitle) -> \(el("calendar.title").label))")
        }
        let line = "Z2 FRAMES \(baseline ? "baseline" : "new") " + report.joined(separator: " | ")
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = env["TT_SHOT_DIR"] { try? line.write(toFile: dir + "/frames-\(baseline ? "baseline" : "new").txt", atomically: true, encoding: .utf8) }
    }
}
