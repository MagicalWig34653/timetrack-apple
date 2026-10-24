import XCTest

/// WM2: new/ended work model versions, time account correction and the statistics charts against a throwaway backend
/// (seeded with 12 weeks of entries; see docs/handoffs/WM2.md). TT_SHOT_DIR/TT_SHOT_PREFIX write screenshots; TT_DARK=1 forces dark mode.
final class WorkModelStatsTests: XCTestCase {
    private var app: XCUIApplication!

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch() throws {
        let env = ProcessInfo.processInfo.environment
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        app.launchEnvironment["TT_DEV_COOKIE"] = try XCTUnwrap(env["TT_DEV_COOKIE"])
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        if env["TT_DARK"] == "1" { app.launchArguments += ["-AppleInterfaceStyle", "Dark"] }
        if let size = env["TT_TEXT_SIZE"] { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
    }

    private func shot(_ name: String) {
        let env = ProcessInfo.processInfo.environment
        let dir = env["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(env["TT_SHOT_PREFIX"] ?? "wm2")-\(name).png"))
    }

    private func scrollTo(_ element: XCUIElement, max: Int = 8) {
        for _ in 0..<max where !element.isHittable { app.swipeUp() }
    }

    /// New version (confirmation) and ending it (confirmation); the timeline shows both versions afterwards.
    func testNewVersionAndEnd() throws {
        try launch()
        app.openSettings()
        let row = el("settings.workmodel")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(el("workmodel.new").waitForExistence(timeout: 10))
        shot("workmodel-list")

        el("workmodel.new").tap()
        let weekly = el("workmodel.field.weekly")
        XCTAssertTrue(weekly.waitForExistence(timeout: 10))
        XCTAssertTrue(el("workmodel.new.consequence").exists)
        shot("workmodel-new")
        weekly.tap()
        weekly.press(forDuration: 1.0)
        if app.menuItems["Alles auswählen"].waitForExistence(timeout: 2) { app.menuItems["Alles auswählen"].tap() }
        weekly.typeText("35:00")
        let create = el("workmodel.new.create")
        scrollTo(create)
        create.tap()
        // Confirmation dialog: cancel first (nothing is saved), then confirm.
        let confirm = app.buttons["Anlegen"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot("workmodel-new-confirm")
        confirm.tap()

        // Back on the list: two versions, the old one ended the day before; the new one can be ended.
        XCTAssertTrue(el("workmodel.end").waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: "workmodel.end").count, 1, "only the open-ended version can be ended")
        shot("workmodel-timeline")

        el("workmodel.end").tap()
        XCTAssertTrue(el("workmodel.end.confirm").waitForExistence(timeout: 10))
        shot("workmodel-end")
        el("workmodel.end.confirm").tap()
        let endConfirm = app.sheets.buttons["Beenden"].exists ? app.sheets.buttons["Beenden"] : app.buttons.matching(identifier: "Beenden").element(boundBy: app.buttons.matching(identifier: "Beenden").count - 1)
        XCTAssertTrue(endConfirm.waitForExistence(timeout: 5))
        endConfirm.tap()
        XCTAssertTrue(el("workmodel.new").waitForExistence(timeout: 15))
        XCTAssertFalse(el("workmodel.end").waitForExistence(timeout: 3), "no open-ended version is left")
        shot("workmodel-ended")
    }

    func testTimeAccountCorrection() throws {
        try launch()
        app.openSettings()
        let row = el("settings.timeaccount")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(el("account.balance").waitForExistence(timeout: 10))
        let before = el("account.balance").label
        shot("account")

        let value = el("account.correction.value")
        scrollTo(value)
        value.tap(); value.typeText("1:00")
        let reason = el("account.correction.reason")
        reason.tap(); reason.typeText("Zeitausgleich Test")
        let save = el("account.correction.save")
        scrollTo(save)
        save.tap()
        let book = app.buttons["Buchen"]
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        shot("account-confirm")
        book.tap()
        XCTAssertTrue(el("account.correction.saved").waitForExistence(timeout: 10))
        XCTAssertNotEqual(el("account.balance").label, before, "the balance reflects the booking")
    }

    func testStatisticsCharts() throws {
        try launch()
        app.openMore()
        let row = el("more.statistics")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(el("stats.balance").waitForExistence(timeout: 20))
        XCTAssertTrue(el("stats.tile.worked").exists)
        shot("stats-top")
        for _ in 0..<2 { app.swipeUp() }
        shot("stats-mid")
        for _ in 0..<3 { app.swipeUp() }
        shot("stats-bottom")
        for _ in 0..<8 { app.swipeDown() }

        // Granularity and basis change reload the charts without leaving the screen.
        let month = app.buttons["Monat"]
        if month.waitForExistence(timeout: 3) { month.tap() }
        XCTAssertTrue(el("stats.balance").waitForExistence(timeout: 15))
        let raw = app.buttons["Ohne Rundung"]
        if raw.exists { raw.tap() }
        XCTAssertTrue(el("stats.target").waitForExistence(timeout: 15))
        shot("stats-month-raw")
    }
}
