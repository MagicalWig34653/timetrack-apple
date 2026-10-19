import XCTest

/// Z1: the slimmed-down "Zeit" tab and the Apple-Calendar-style "Kalender" tab against the throwaway backend (skipped without TT_DEV_SERVER).
/// Screenshots go to TT_SHOT_DIR (prefix TT_SHOT_PREFIX, default "z1"); TT_SHOT_SCHEME (light|dark) overrides the appearance.
final class TimeCalendarTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "z1"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "z1"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
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

    /// One list, no segments: week header with total, the days below, details as a drill-down.
    func testTimeTab() throws {
        try launch()
        open("Zeit", "time")
        XCTAssertTrue(el("time.week_details").waitForExistence(timeout: 15))
        XCTAssertFalse(app.segmentedControls["time.segments"].exists, "the Liste/Woche/Planen switch is gone")
        sleep(1)
        shot("time")
        el("time.week_details").tap()
        XCTAssertTrue(el("week.summary").waitForExistence(timeout: 15))
        sleep(1)
        shot("time-details")
    }

    /// Month grid with the selected day's details below; swiping pages between months.
    func testCalendarTab() throws {
        try launch()
        open("Kalender", "calendar")
        XCTAssertTrue(el("calendar.title").waitForExistence(timeout: 10))
        XCTAssertTrue(el("day.vacation").waitForExistence(timeout: 10), "details of the selected day show without opening a sheet")
        sleep(1)
        shot("calendar")
        let before = el("calendar.title").label
        let grid = el("calendar.title")
        grid.swipeLeft() // not on the grid: no month change expected
        XCTAssertEqual(el("calendar.title").label, before)
        el("calendar.next").tap()
        sleep(1)
        XCTAssertNotEqual(el("calendar.title").label, before)
        shot("calendar-next-month")
        el("calendar.today").tap()
        XCTAssertEqual(el("calendar.title").label, before)
    }
}
