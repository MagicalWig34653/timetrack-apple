import XCTest

/// A10: creates a vacation range, a sick day with a pending sick note, a custom day; edits and cancels them in the Kalender tab
/// and stores screenshots in TT_SHOT_DIR (prefix TT_SHOT_PREFIX). Needs the throwaway server environment; skipped otherwise.
final class PlanningFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "plan"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func iso(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func testCalendarPlanningFlow() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "plan"
        if env["TT_SHOT_LANDSCAPE"] != nil { XCUIDevice.shared.orientation = .landscapeLeft }
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
        shot("today")

        open("Kalender", "calendar")
        XCTAssertTrue(el("calendar.title").waitForExistence(timeout: 10))
        sleep(1)
        shot("calendar-month")

        // Dates: vacation = Monday..Wednesday of next week, sick = Thursday, custom day = Friday of next week.
        let today = Date()
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: today) // 1 = Sunday
        let toMonday = (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7
        let monday = Calendar.current.date(byAdding: .day, value: toMonday, to: today)!
        func day(_ offset: Int) -> String { iso(Calendar.current.date(byAdding: .day, value: offset, to: monday)!) }

        // 1) Range selection by long press + tap, then vacation.
        // Next week may start in the following month (the grid shows one month).
        if !el("day.\(day(0))").exists { app.buttons["calendar.next"].tap() }
        let first = el("day.\(day(0))")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.press(forDuration: 0.9)
        XCTAssertTrue(el("range.cancel").waitForExistence(timeout: 5))
        el("day.\(day(2))").tap()
        sleep(1)
        shot("calendar-range")
        el("range.vacation").tap()
        XCTAssertTrue(el("absence.save").waitForExistence(timeout: 5))
        sleep(1)
        shot("editor-vacation")
        el("absence.save").tap()
        XCTAssertTrue(el("absence.save").waitForNonExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(el("day.\(day(1))").label.contains("Urlaub"), "cell label: \(el("day.\(day(1))").label)")
        shot("calendar-after-vacation")

        // 2) Sick day with pending sick note via the day sheet.
        el("day.\(day(3))").tap()
        XCTAssertTrue(el("day.sick").waitForExistence(timeout: 5))
        sleep(1)
        shot("daysheet")
        el("day.sick").tap()
        XCTAssertTrue(el("absence.document").waitForExistence(timeout: 5))
        el("absence.document").tap()
        app.buttons["Noch einzureichen"].firstMatch.tap()
        sleep(1)
        shot("editor-sick")
        el("absence.save").tap()
        XCTAssertTrue(el("absence.save").waitForNonExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(el("day.\(day(3))").label.contains("Krank"), "cell label: \(el("day.\(day(3))").label)")

        // 3) Sick note set to submitted through the context menu of the row in the day detail.
        if !el("day.sick").exists { el("day.\(day(3))").tap() }
        let row = el("absence.row")
        if row.waitForExistence(timeout: 5) {
            row.press(forDuration: 1.0)
            if app.buttons["Krankschein als eingereicht markieren"].waitForExistence(timeout: 3) { app.buttons["Krankschein als eingereicht markieren"].tap() }
            else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap() } // dismiss the menu without hitting the inline day actions
        }
        sleep(1)
        shot("daysheet-sick")
        if el("daysheet.done").exists { el("daysheet.done").tap() }

        // 4) Custom day.
        el("day.\(day(4))").tap()
        XCTAssertTrue(el("day.custom").waitForExistence(timeout: 5))
        el("day.custom").tap()
        let name = app.textFields["Bezeichnung"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Brückentag")
        el("custom.save").tap()
        XCTAssertTrue(el("custom.save").waitForNonExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(el("day.\(day(4))").label.contains("Brückentag"), "cell label: \(el("day.\(day(4))").label)")
        shot("calendar-custom")
        if el("daysheet.done").exists { el("daysheet.done").tap() }

        // 5) Edit the vacation (note), then cancel it.
        el("day.\(day(1))").tap()
        XCTAssertTrue(el("absence.row").waitForExistence(timeout: 5))
        el("absence.row").tap()
        XCTAssertTrue(el("absence.note").waitForExistence(timeout: 5))
        el("absence.note").tap()
        el("absence.note").typeText("Herbsturlaub")
        shot("editor-edit")
        el("absence.save").tap()
        XCTAssertTrue(el("absence.save").waitForNonExistence(timeout: 10))
        sleep(1)
        if !el("absence.row").exists { el("day.\(day(1))").tap() }
        XCTAssertTrue(el("absence.row").waitForExistence(timeout: 5))
        el("absence.row").tap()
        XCTAssertTrue(el("absence.cancel").waitForExistence(timeout: 5))
        app.swipeUp()
        shot("editor-bottom")
        el("absence.cancel").tap()
        XCTAssertTrue(app.buttons["Ja, stornieren"].waitForExistence(timeout: 5))
        app.buttons["Ja, stornieren"].tap()
        XCTAssertTrue(el("absence.cancel").waitForNonExistence(timeout: 10))
        sleep(1)
        XCTAssertFalse(el("day.\(day(1))").label.contains("Urlaub"), "vacation still shown after cancel")
        if el("daysheet.done").exists { el("daysheet.done").tap() }

        // 6) Re-create one vacation so the Urlaub tab has data, then look at it.
        if !el("day.\(day(7))").exists { app.buttons["calendar.next"].tap() }
        el("day.\(day(7))").tap()
        XCTAssertTrue(el("day.vacation").waitForExistence(timeout: 5))
        el("day.vacation").tap()
        XCTAssertTrue(el("absence.save").waitForExistence(timeout: 5))
        el("absence.save").tap()
        XCTAssertTrue(el("absence.save").waitForNonExistence(timeout: 10))
        if el("daysheet.done").exists { el("daysheet.done").tap() }
        shot("calendar-final")

        open("Urlaub", "vacation")
        XCTAssertTrue(app.staticTexts["Urlaubskonto"].waitForExistence(timeout: 10))
        sleep(1)
        shot("vacation")
        // S2: the vacation settings sheet is reached from Einstellungen › Urlaubsanspruch (no longer from the Urlaub tab).
        app.openSettings()
        XCTAssertTrue(el("settings.vacation").waitForExistence(timeout: 10))
        el("settings.vacation").tap()
        XCTAssertTrue(el("settings.save").waitForExistence(timeout: 5))
        sleep(1)
        shot("vacation-settings")
        el("settings.done").tap()
    }

    private func open(_ title: String, _ id: String) {
        let tab = app.tabBars.buttons[title]
        if tab.exists { tab.tap() } else { el("sidebar.\(id)").tap() }
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }
}
