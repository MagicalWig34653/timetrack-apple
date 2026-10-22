import XCTest

/// Z3: screenshots of the Zeit screen states for the design review (month, week, range mode, planning mode, holiday/vacation day).
/// TT_SHOT_DIR/TT_SHOT_PREFIX as usual; TT_TEXT_SIZE (content size category) and TT_SHOT_SCHEME (light|dark) override the appearance.
final class TimePolishShotTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "z3"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch(zoom: String) throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "z3"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-time.zoom", zoom]
        if let size = env["TT_TEXT_SIZE"] { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        if let scheme = env["TT_SHOT_SCHEME"] { app.launchArguments += ["-appearance.scheme", scheme] }
        app.launch()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
        let tab = app.tabBars.buttons["Zeit"]
        if tab.exists { tab.tap() } else { el("sidebar.time").tap() }
        sleep(2)
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }

    func testMonthStates() throws {
        try launch(zoom: "month")
        XCTAssertTrue(el("calendar.title").waitForExistence(timeout: 15))
        shot("month")
        // Day with vacation (three weeks after this Monday).
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let monday = cal.dateInterval(of: .weekOfYear, for: Date())!.start
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        let vacation = el("day.\(f.string(from: cal.date(byAdding: .day, value: 21, to: monday)!))")
        if !vacation.exists { app.buttons["calendar.next"].tap(); sleep(1) }
        if vacation.waitForExistence(timeout: 3) { vacation.tap(); sleep(1); shot("month-vacation") }
        if el("time.more").exists {
            el("time.more").tap()
            if el("calendar.range").waitForExistence(timeout: 3) { el("calendar.range").tap(); sleep(1); shot("month-range") }
        }
    }

    func testWeekStates() throws {
        try launch(zoom: "week")
        XCTAssertTrue(el("time.week_details").waitForExistence(timeout: 15))
        shot("week")
        app.swipeUp(); sleep(1)
        shot("week-scrolled")
        app.swipeDown()
        if el("week.plan").waitForExistence(timeout: 3) { el("week.plan").tap(); sleep(2); shot("week-planning") }
    }
}
