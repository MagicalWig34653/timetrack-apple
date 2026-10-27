import XCTest

/// P13: several plan blocks per day against the throwaway backend (skipped without TT_DEV_SERVER). Needs the seed script
/// `scripts/seed-p13.py` (backend >= contract 0.35.0): split days (school + work, office + travel + customer, home) in this and next week.
final class PlanBlocksTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "p13"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch(zoom: String = "week") throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "p13"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-time.zoom", zoom]
        if let scheme = env["TT_SHOT_SCHEME"] { app.launchArguments += ["-appearance.scheme", scheme] }
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }

    private func openZeit() {
        let tab = app.tabBars.buttons["Zeit"]
        if tab.exists { tab.tap() } else { el("sidebar.time").tap() }
    }

    private func day(offset: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        let monday = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
        let date = calendar.date(byAdding: .day, value: offset, to: monday)!
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func testWeekListShowsEachBlockWithDifferenceAndHints() throws {
        try launch()
        openZeit()
        let monday = day(offset: 0)
        XCTAssertTrue(el("time.plan_blocks.\(monday)").waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["08:00–12:00 Schule"].exists)
        sleep(1)
        shot("week-list")
    }

    func testSharedViewShowsBlocksWithoutPlacesAndNotes() throws {
        try launch()
        let tab = app.tabBars.buttons["Zeit"]
        if tab.exists { tab.tap() } else { el("sidebar.time").tap() }
        XCTAssertTrue(el("time.more").waitForExistence(timeout: 15))
        el("time.more").tap()
        el("time.planning_area").tap()
        XCTAssertTrue(el("planning.shares").waitForExistence(timeout: 15))
        el("planning.shares").tap()
        XCTAssertTrue(el("share.in.Ben Beispiel").waitForExistence(timeout: 15))
        el("share.in.Ben Beispiel").tap()
        XCTAssertTrue(el("shared.load").waitForExistence(timeout: 10))
        sleep(2)
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'share.plan.'"))
        XCTAssertGreaterThan(rows.count, 0)
        XCTAssertTrue(app.staticTexts["08:00–12:15 Arbeit"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Arbeit'")).count > 0)
        shot("shared")
    }
}
