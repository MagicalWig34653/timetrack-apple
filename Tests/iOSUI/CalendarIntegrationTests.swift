import XCTest

/// E1: the "Kalender" settings page (permission flow, calendar choice, write switch) and the day-view event section with the
/// "Termin als Zeitabschnitt vorschlagen" sheet, against the in-memory calendar (`TT_DEV_CALENDAR_FAKE`; no system permission sheet)
/// and a recording stub server. Screenshots go to TT_SHOT_DIR.
final class CalendarIntegrationTests: XCTestCase {
    private var app: XCUIApplication!

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch(_ page: String) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment[page] = "1"
        app.launchEnvironment["TT_DEV_CALENDAR_FAKE"] = "1"
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
    }

    func testSettingsPermissionFlow() throws {
        launch("TT_DEV_CALENDAR_PAGE")
        XCTAssertTrue(el("calendar.allow").waitForExistence(timeout: 15))
        XCTAssertEqual(el("calendar.access.status").label, "Nicht angefragt")
        XCTAssertFalse(el("calendar.write").exists, "nothing but the permission step before access is granted")
        shot("cal-settings-before")

        el("calendar.allow").tap()
        XCTAssertTrue(el("calendar.mode.Arbeit").waitForExistence(timeout: 10))
        XCTAssertEqual(el("calendar.access.status").label, "Erlaubt")
        shot("cal-settings-granted")

        XCTAssertTrue(el("calendar.mode.Arbeit").buttons["Aus"].isSelected, "every calendar starts off")
        el("calendar.mode.Arbeit").buttons["Lesen"].tap()
        XCTAssertTrue(el("calendar.mode.Arbeit").buttons["Lesen"].isSelected)
        XCTAssertTrue(el("calendar.write.none").waitForExistence(timeout: 5), "reading alone never writes")
        shot("cal-settings-read")
    }

    /// E2: per-calendar read+write, planned vacation and sick days written as all-day events, change and void followed, cleanup button.
    func testReadWriteWritesAbsencesAndCleanupRemovesThem() throws {
        launch("TT_DEV_CALENDAR_WRITE")
        XCTAssertTrue(el("calendar.allow").waitForExistence(timeout: 15))
        el("calendar.allow").tap()
        XCTAssertTrue(el("calendar.mode.Arbeit").waitForExistence(timeout: 10))
        XCTAssertFalse(el("calendar.mode.Feiertage").buttons["Schreiben"].exists, "a subscribed calendar offers no write mode")

        el("calendar.mode.Arbeit").buttons["Schreiben"].tap()
        el("calendar.mode.Familie").buttons["Lesen"].tap()
        shot("e2-modes")

        el("demo.sync").tap()
        let written = el("demo.written")
        XCTAssertTrue(written.waitForExistence(timeout: 5))
        XCTAssertTrue(written.label.contains("Urlaub (geplant) | Arbeit"), written.label)
        XCTAssertTrue(written.label.contains("Krank | Arbeit"), written.label)
        XCTAssertFalse(written.label.contains("Familie"), "read-only calendars receive nothing: \(written.label)")
        XCTAssertFalse(written.label.contains("Arzt"), "notes never reach the calendar")
        XCTAssertFalse(written.label.contains("Grippe"), "notes never reach the calendar")
        shot("e2-written")

        el("demo.approve").tap()
        XCTAssertTrue(written.label.contains("Urlaub (genehmigt)"), written.label)
        el("demo.void").tap()
        XCTAssertFalse(written.label.contains("Urlaub"), "a voided absence disappears: \(written.label)")
        XCTAssertTrue(written.label.contains("Krank"), written.label)

        el("demo.sync").tap()
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(el("calendar.remove").waitForExistence(timeout: 5))
        shot("e2-cleanup")
        el("calendar.remove").tap()
        XCTAssertTrue(el("calendar.remove.confirm").waitForExistence(timeout: 5))
        shot("e2-confirm")
        el("calendar.remove.confirm").tap()
        XCTAssertTrue(el("calendar.remove.result").waitForExistence(timeout: 5))
        XCTAssertTrue(el("calendar.remove.result").label.contains("2 Termine"), el("calendar.remove.result").label)
        shot("e2-removed")
    }

    func testDayViewShowsEventsAndDraftNeedsExplicitKind() throws {
        launch("TT_DEV_CALENDAR_DAY")
        let rows = app.descendants(matching: .any).matching(identifier: "event.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(rows.count, 4)
        shot("cal-day")

        let suggest = app.buttons.matching(identifier: "event.suggest").element(boundBy: 1) // "Berufsschule Informatik"
        XCTAssertTrue(suggest.waitForExistence(timeout: 5))
        suggest.tap()
        let found = el("eventdraft.kind.work").waitForExistence(timeout: 5)
        shot("cal-draft")
        XCTAssertTrue(found)
        XCTAssertFalse(app.buttons["eventdraft.save"].isEnabled, "saving needs an explicit kind")
        shot("cal-draft")

        el("eventdraft.kind.school").tap()
        XCTAssertTrue(app.buttons["eventdraft.save"].isEnabled)
        shot("cal-draft-kind")
        app.buttons["eventdraft.save"].tap()

        let sent = el("demo.sent")
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(8)
        while !sent.label.contains("school"), Date() < deadline { usleep(250_000) }
        XCTAssertTrue(sent.label.contains("\"kind\":\"school\""), sent.label)
        XCTAssertFalse(sent.label.contains("Berufsschule"), sent.label)
        XCTAssertFalse(sent.label.contains("Informatik"), sent.label)
        shot("cal-sent")
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
