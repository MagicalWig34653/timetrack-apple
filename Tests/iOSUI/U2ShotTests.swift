import XCTest

/// U2: screenshots of the three Zeit views (month, week, planner) for before/after comparison (skipped without TT_DEV_SERVER).
final class U2ShotTests: XCTestCase {
    private var app: XCUIApplication!
    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch(zoom: String) throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-time.zoom", zoom]
        if let scheme = env["TT_SHOT_SCHEME"] { app.launchArguments += ["-appearance.scheme", scheme] }
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
        let tab = app.tabBars.buttons["Zeit"]
        if tab.exists { tab.tap() } else { el("sidebar.time").tap() }
        XCTAssertTrue(el("calendar.title").waitForExistence(timeout: 20))
        sleep(3)
    }

    private func shot(_ name: String) {
        let env = ProcessInfo.processInfo.environment
        let dir = env["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(env["TT_SHOT_PREFIX"] ?? "u2")-\(name).png"))
    }

    func testMonthShot() throws {
        try launch(zoom: "month")
        shot("month")
    }

    func testWeekShot() throws {
        try launch(zoom: "week")
        shot("week")
    }

    func testPlannerShot() throws {
        try launch(zoom: "week")
        let plan = el("week.plan")
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        plan.tap()
        sleep(3)
        shot("planner")
    }

    /// U2: the month is a vertical list; scrolling changes the header month, a tap opens the day sheet, an entry opens the editor.
    func testMonthListScrollsTapsAndOpensEditor() throws {
        try launch(zoom: "month")
        let start = el("calendar.title").label
        let list = el("month.list")
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        list.swipeUp(velocity: .fast)
        list.swipeUp(velocity: .fast)
        list.swipeUp(velocity: .fast)
        sleep(1)
        XCTAssertNotEqual(el("calendar.title").label, start, "scrolling must move the month title")
        shot("month-scrolled")
        XCTAssertTrue(el("month.jump_today").waitForExistence(timeout: 5))
        el("month.jump_today").tap()
        sleep(2)
        XCTAssertEqual(el("calendar.title").label, start)
        // Tap today: the day sheet opens with the entries; tapping an entry opens the editor on top (sheet chain).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"
        let day = el("day.\(f.string(from: Date()))")
        XCTAssertTrue(day.waitForExistence(timeout: 10))
        day.tap()
        XCTAssertTrue(el("month.day_sheet").waitForExistence(timeout: 10))
        sleep(2)
        shot("month-sheet")
    }
}
