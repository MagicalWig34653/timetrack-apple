import XCTest

/// V3: vacation ring with planned share, absence filter and sort, attachment preview against the throwaway backend
/// (seed-throwaway.py + seed-vacation-v3.py; skipped without TT_DEV_SERVER). Screenshots go to TT_SHOT_DIR (prefix TT_SHOT_PREFIX).
final class VacationV3Tests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "v3"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "v3"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        if let scheme = env["TT_SHOT_SCHEME"] { app.launchArguments += ["-appearance.scheme", scheme] }
        // start every run without a remembered selection
        app.launchArguments += ["-vacation.absenceListOptions.v1", ""]
        app.launch()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }

    private func openVacation() {
        let tab = app.tabBars.buttons["Urlaub"]
        if tab.exists { tab.tap() } else { el("sidebar.vacation").tap() }
        XCTAssertTrue(app.staticTexts["Urlaubskonto"].waitForExistence(timeout: 10))
        XCTAssertTrue(el("absence.filter").waitForExistence(timeout: 10) || { app.swipeUp(); return el("absence.filter").exists }())
    }

    func testRingFilterSortAndAttachments() throws {
        try launch()
        openVacation()
        sleep(1)
        shot("ring")
        XCTAssertTrue(app.staticTexts["Geplant (noch nicht genehmigt)"].exists, "legend names the planned share")
        let ring = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Urlaubsverbrauch'")).firstMatch
        XCTAssertTrue(ring.exists, "ring has a spoken summary")
        XCTAssertTrue(ring.label.contains("8 Tage genommen oder genehmigt") && ring.label.contains("10 Tage geplant"), ring.label)

        // list: grouped by default, paperclip on the two absences with attachments
        el("absence.filter").tap()
        XCTAssertTrue(el("absence.filter.done").waitForExistence(timeout: 5))
        shot("filter-sheet")
        el("absence.filter.kind.vacation").tap()
        el("absence.filter.status.planned").tap()
        shot("filter-selected")
        el("absence.filter.done").tap()
        XCTAssertTrue(el("absence.filter.reset").waitForExistence(timeout: 5), "reset appears with active filters")
        let rows = app.buttons.matching(identifier: "absence.row")
        XCTAssertEqual(rows.count, 2, "vacation + planned = the two planned vacations")
        app.swipeUp()
        shot("filtered")
        app.swipeDown()

        // remembered: relaunch keeps the selection
        app.terminate()
        app.launchArguments = app.launchArguments.filter { $0 != "-vacation.absenceListOptions.v1" && $0 != "" }
        app.launch()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
        openVacation()
        XCTAssertTrue(el("absence.filter.reset").waitForExistence(timeout: 5), "selection survives a relaunch")

        // attachment filter: only absences with an attachment (clears kind and status first)
        el("absence.filter.reset").tap()
        el("absence.filter").tap()
        XCTAssertTrue(el("absence.filter.done").waitForExistence(timeout: 5))
        let segments = el("absence.attachment")
        segments.buttons["Mit Anhang"].tap()
        el("absence.filter.done").tap()
        XCTAssertEqual(app.buttons.matching(identifier: "absence.row").count, 2)
        XCTAssertEqual(app.buttons.matching(identifier: "absence.attachments").count, 2)
        app.swipeUp()
        shot("with-attachment")
        app.swipeDown()

        // preview the PDF
        app.buttons.matching(identifier: "absence.attachments").firstMatch.tap()
        XCTAssertTrue(el("attachment.row").waitForExistence(timeout: 10))
        shot("attachments")
        el("attachment.row").firstMatch.tap()
        sleep(3)
        shot("preview")
        for label in ["Schließen", "Close", "Done"] where app.buttons[label].exists { app.buttons[label].firstMatch.tap(); break }
        XCTAssertTrue(el("attachments.done").waitForExistence(timeout: 10), "preview closed, sheet visible again")
        el("attachments.done").tap()

        // sort by status, reversed: grouping gives way to one result list
        el("absence.filter.reset").tap()
        el("absence.filter").tap()
        XCTAssertTrue(el("absence.filter.done").waitForExistence(timeout: 5))
        el("absence.sort").buttons["Status"].tap()
        shot("sort-status")
        el("absence.filter.done").tap()
        XCTAssertTrue(app.staticTexts["Ergebnisse"].waitForExistence(timeout: 5))
        app.swipeUp()
        shot("sorted")
    }
}
