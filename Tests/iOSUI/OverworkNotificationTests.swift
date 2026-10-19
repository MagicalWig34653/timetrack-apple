import XCTest

/// OT1: the overwork notification settings page (`TT_DEV_OVERWORK_PAGE` shows it directly, no server needed). The first activation shows
/// the system permission prompt.
final class OverworkNotificationTests: XCTestCase {
    func testActivationAsksForPermissionAndKeepsSwitchesSeparate() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_OVERWORK_PAGE"] = "1"
        app.launch()
        let limits = app.switches["overwork.limits"]
        XCTAssertTrue(limits.waitForExistence(timeout: 15))
        // The switches persist in the App Group between runs: bring a previous run's state back to the default first.
        for id in ["overwork.limits", "overwork.planned_end", "overwork.break"] where app.switches[id].value as? String == "1" {
            app.switches[id].coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.switches["overwork.limits"].waitForExistence(timeout: 5))
        XCTAssertEqual(limits.value as? String, "0", "off after reset")
        XCTAssertEqual(app.switches["overwork.planned_end"].value as? String, "0")
        XCTAssertEqual(app.switches["overwork.break"].value as? String, "0")
        shot("ot1-overwork-off")
        limits.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Erlauben", "Allow"] {
            let button = springboard.alerts.buttons[label]
            if button.waitForExistence(timeout: 5) { button.tap(); break }
        }
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: limits)
        XCTAssertEqual(XCTWaiter().wait(for: [on], timeout: 15), .completed, "the switch turns on once permission is granted")
        XCTAssertEqual(limits.value as? String, "1")
        XCTAssertEqual(app.switches["overwork.planned_end"].value as? String, "0")
        XCTAssertEqual(app.switches["overwork.break"].value as? String, "0")
        shot("ot1-overwork-on")
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
