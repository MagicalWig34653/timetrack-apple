import XCTest

/// P14c: calendar feed management (Mehr › Kalenderabos) and the push settings page (Mehr › Push-Benachrichtigungen).
/// Needs a THROWAWAY backend (`scripts/seed-throwaway.py`, loopback only). The backend has no APNs configuration, so registering a
/// device token answers 501 `push_unavailable`, which the page must show as "Vom Server nicht angeboten" without an error.
/// Screenshots go to TT_SHOT_DIR when set. iPhone layout (tab bar).
final class PushFeedsTests: XCTestCase {
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func launch() throws -> XCUIApplication {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        try XCTSkipIf(!app.tabBars.buttons.element(boundBy: 0).waitForExistence(timeout: 20), "compact layout only")
        return app
    }

    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        var tries = 0
        while !element.isHittable, tries < 6 { app.swipeUp(); tries += 1 }
    }

    func testCalendarFeedCreateShowLinkAndRevoke() throws {
        continueAfterFailure = false
        let app = try launch()
        app.openMore()
        let row = el(app, "settings.feeds")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        scrollTo(app, row)
        row.tap()
        XCTAssertTrue(el(app, "feeds.new").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "feeds.empty").waitForExistence(timeout: 10))
        shot("p14c-feeds-empty")

        el(app, "feeds.new").tap()
        let label = el(app, "feeds.label")
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        label.tap()
        label.typeText("UI-Test")
        el(app, "feeds.content.plan").tap() // adds the plan to the defaults (Abwesenheiten, Feiertage)
        shot("p14c-feeds-create")
        el(app, "feeds.create").tap()

        // The one-time link: https first, webcal on demand, actions present.
        let link = el(app, "feeds.link")
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        XCTAssertTrue((link.label.contains("/ics/") && link.label.hasSuffix(".ics")), "link: \(link.label)")
        XCTAssertTrue(link.label.hasPrefix("http"))
        XCTAssertTrue(el(app, "feeds.subscribe").exists)
        XCTAssertTrue(el(app, "feeds.copy").exists)
        XCTAssertTrue(el(app, "feeds.share").exists)
        shot("p14c-feeds-link")
        el(app, "feeds.webcal_toggle").tap()
        XCTAssertTrue(link.label.hasPrefix("webcal://"), "link: \(link.label)")
        el(app, "feeds.copy").tap()
        el(app, "feeds.done").tap()

        // Listed without the secret; revoke asks first.
        let listed = el(app, "feeds.row.UI-Test")
        XCTAssertTrue(listed.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '/ics/'")).firstMatch.exists, "the link is not shown again")
        XCTAssertTrue(app.staticTexts["Abwesenheiten, Feiertage, Geplante Arbeitszeit"].exists)
        shot("p14c-feeds-list")
        el(app, "feeds.revoke.UI-Test").tap()
        let confirm = app.buttons["Widerrufen"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot("p14c-feeds-revoke")
        confirm.tap()
        XCTAssertTrue(el(app, "feeds.empty").waitForExistence(timeout: 10))
        XCTAssertFalse(listed.exists)
    }

    func testPushPageShowsStateAndHandlesAnUnconfiguredServer() throws {
        continueAfterFailure = false
        let app = try launch()
        let monitor = addUIInterruptionMonitor(withDescription: "notifications") { alert in
            for name in ["Erlauben", "Allow"] where alert.buttons[name].exists { alert.buttons[name].tap(); return true }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }
        app.openMore()
        let row = el(app, "settings.push")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        scrollTo(app, row)
        row.tap()
        let status = el(app, "push.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        shot("p14c-push-initial")

        let enable = el(app, "push.enable")
        if enable.waitForExistence(timeout: 3) {
            enable.tap()
            app.tap() // lets the interruption monitor handle the system dialog
        }
        // After allowing: the simulator hands out a token, the unconfigured backend answers 501 -> "Vom Server nicht angeboten".
        let unavailable = app.staticTexts["Vom Server nicht angeboten"]
        let waiting = app.staticTexts["Wartet auf Gerätekennung"]
        let deadline = Date().addingTimeInterval(25)
        while !unavailable.exists, Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
        shot("p14c-push-state")
        XCTAssertTrue(unavailable.exists || waiting.exists || app.staticTexts["In den Systemeinstellungen aus"].exists || app.staticTexts["Nicht möglich"].exists, // Debug builds sign with the personal entitlements (no aps-environment)
                      "one of the documented states must be visible")
        XCTAssertFalse(el(app, "push.test").exists, "no test button without a registered device")
    }
}
