import XCTest

/// R3: the reminder settings page (`TT_DEV_REMINDERS_PAGE` shows it directly, no server needed). The first activation shows the
/// system permission prompt, which the interruption monitor answers.
final class VacationReminderTests: XCTestCase {
    func testActivationAsksForPermissionAndShowsOptions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_REMINDERS_PAGE"] = "1"
        addUIInterruptionMonitor(withDescription: "notifications") { alert in
            for label in ["Erlauben", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        let toggle = app.switches["reminders.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        shot("r3-reminders-off")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() // the switch itself, right edge of the row
        // The system prompt belongs to SpringBoard.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Erlauben", "Allow"] {
            let button = springboard.alerts.buttons[label]
            if button.waitForExistence(timeout: 5) { button.tap(); break }
        }
        let fourteen = app.switches["reminders.lead.14"]
        XCTAssertTrue(fourteen.waitForExistence(timeout: 10), "options appear once permission is granted")
        XCTAssertEqual(fourteen.value as? String, "1")
        XCTAssertEqual(app.switches["reminders.lead.3"].value as? String, "1")
        XCTAssertEqual(app.switches["reminders.lead.7"].value as? String, "0")
        XCTAssertTrue(app.datePickers["reminders.time"].exists || app.staticTexts["Uhrzeit"].exists)
        shot("r3-reminders-on")
        app.swipeUp()
        shot("r3-reminders-on-bottom")
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
