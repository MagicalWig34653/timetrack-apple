import XCTest

/// Exercises the Focus filter page without a server: `TT_DEV_FOCUS_PAGE` shows the page directly, `TT_DEV_FOCUS_FAKE` swaps the
/// session/timer for an in-memory fake. A real Focus cannot be toggled in the simulator, so the "Fokus an/aus" test buttons
/// stand in for the system callback.
final class FocusFilterTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_FOCUS_PAGE"] = "1"
        app.launchEnvironment["TT_DEV_FOCUS_FAKE"] = "1"
        app.launchEnvironment["TT_DEV_FOCUS_RESET"] = "1"
        addUIInterruptionMonitor(withDescription: "notifications") { alert in
            for label in ["Erlauben", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    func testExplainerAndDryRun() throws {
        app.launch()
        XCTAssertTrue(app.staticTexts["focus.path"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["focus.path"].label, "Einstellungen › Fokus › [dein Fokus] › Fokusfilter › Timetrack")
        XCTAssertTrue(app.staticTexts["focus.status.none"].exists || app.otherElements["focus.status.none"].exists)
        shot("focus-top")
        app.swipeUp()
        shot("focus-middle")
        app.swipeUp()
        shot("focus-test")

        let on = app.buttons["focus.test.on"]
        scrollTo(on)
        on.tap()
        let result = app.staticTexts["focus.test.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Nur Vorschau"), result.label)
        XCTAssertTrue(result.label.contains("Würde fragen"), result.label)
        app.swipeUp()
        shot("focus-dry")
    }

    func testRealRunPostsNotificationAndLogs() throws {
        app.launch()
        let ask = app.buttons["focus.notify.ask"]
        if ask.waitForExistence(timeout: 10) {
            ask.tap()
            app.tap() // lets the interruption monitor answer the system alert
            sleep(1)
        }
        let real = app.switches["focus.test.real"]
        scrollTo(real)
        real.tap()
        app.buttons["focus.test.on"].tap()
        let appeared = app.staticTexts["focus.test.result"].waitForExistence(timeout: 15)
        if !appeared { shot("focus-realrun-failure") }
        XCTAssertTrue(appeared)
        sleep(1)
        shot("focus-banner")
        XCTAssertTrue(app.staticTexts["focus.log.list"].exists || app.otherElements["focus.log.list"].waitForExistence(timeout: 3))
        app.swipeUp()
        shot("focus-log")

        // Direct mode with the fake backend: start, then stop what the Focus started.
        app.swipeDown(); app.swipeDown()
        scrollTo(app.segmentedControls["focus.test.mode"])
        app.segmentedControls["focus.test.mode"].buttons["Automatisch"].tap()
        app.buttons["focus.test.on"].tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["focus.test.result"].label.contains("gestartet"), app.staticTexts["focus.test.result"].label)
        app.buttons["focus.test.off"].tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["focus.test.result"].label.contains("gestoppt"), app.staticTexts["focus.test.result"].label)
    }

    // MARK: F3: delivery pipeline and diagnostics

    /// An empty delivery (what iOS sends when a Focus ends) without an active Focus is shown, not swallowed.
    func testSimulatedEndWithoutActiveFocusIsVisible() throws {
        app.launchEnvironment["TT_DEV_FOCUS_RESET"] = "1"
        app.launchEnvironment["TT_DEV_FOCUS_SIMULATE"] = "on:off:work:Arbeit,off,off"
        app.launch()
        let kind = app.staticTexts["focus.delivery.kind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 15))
        // on(mode off) -> off -> off: the last delivery is an end without an active Focus.
        XCTAssertTrue(waitForLabel(kind, containing: "ohne aktiven Fokus"), kind.label)
        XCTAssertTrue(app.staticTexts["focus.delivery.parameters"].label.contains("keine Angaben"))
        XCTAssertTrue(app.staticTexts["focus.delivery.result"].exists)
        shot("focus-delivery-end")
    }

    /// Offline direct start: the action is queued and shown as waiting; going online and "Jetzt senden" delivers it.
    func testOfflineStartIsQueuedAndRetried() throws {
        app.launchEnvironment["TT_DEV_FOCUS_RESET"] = "1"
        app.launchEnvironment["TT_DEV_FOCUS_SIMULATE"] = "offline,on:direct:work:Arbeit"
        app.launch()
        let pending = app.staticTexts["focus.delivery.pending"]
        XCTAssertTrue(pending.waitForExistence(timeout: 15))
        XCTAssertTrue(pending.label.contains("wartet"), pending.label)
        XCTAssertTrue(app.staticTexts["focus.delivery.result"].label.contains("erneut versucht"), app.staticTexts["focus.delivery.result"].label)
        shot("focus-delivery-queued")

        let offline = app.switches["focus.sim.offline"]
        scrollTo(offline)
        offline.tap() // back online
        let retry = app.buttons["focus.delivery.retry"]
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        scrollTo(retry)
        retry.tap()
        XCTAssertTrue(waitForGone(app.staticTexts["focus.delivery.pending"]))
        shot("focus-delivery-retried")
    }

    /// The same activation twice in a row is one delivery.
    func testDuplicateDeliveryIsIgnored() throws {
        app.launchEnvironment["TT_DEV_FOCUS_RESET"] = "1"
        app.launchEnvironment["TT_DEV_FOCUS_SIMULATE"] = "on:direct:work:Arbeit,on:direct:work:Arbeit"
        app.launch()
        let kind = app.staticTexts["focus.delivery.kind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForLabel(kind, containing: "Doppelte Meldung"), kind.label)
        shot("focus-delivery-duplicate")
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label.contains(text) { return true }
            usleep(300_000)
        }
        return false
    }

    private func waitForGone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(300_000)
        }
        return false
    }

    /// Best effort: looks for the filter in the simulator's own Settings app (Focus > Work > Focus filters > add). Skips when the
    /// simulator has no Focus settings or the path differs.
    func testFilterListedInSystemSettings() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let focus = settings.staticTexts["Focus"]
        var tries = 0
        while !focus.exists && tries < 6 { settings.swipeUp(); tries += 1 }
        try XCTSkipUnless(focus.exists, "no Focus row in the simulator's Settings")
        focus.tap()
        shotSettings("system-focus-1")
        let work = settings.staticTexts["Work"]
        try XCTSkipUnless(work.waitForExistence(timeout: 5), "no Work Focus")
        work.tap()
        shotSettings("system-focus-2")
        var swipes = 0
        let add = settings.buttons["Add Filter"]
        while !add.exists && swipes < 6 { settings.swipeUp(); swipes += 1 }
        try XCTSkipUnless(add.exists, "no Add Filter row")
        add.tap()
        shotSettings("system-focus-3")
        XCTAssertTrue(settings.staticTexts["Timetrack"].waitForExistence(timeout: 5), "Timetrack missing from the filter list")
    }

    private func shotSettings(_ name: String) { shot(name) }

    private func scrollTo(_ element: XCUIElement) {
        var attempts = 0
        while !element.isHittable && attempts < 8 { app.swipeUp(); attempts += 1 }
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
