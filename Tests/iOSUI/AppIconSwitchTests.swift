import XCTest

/// IC1: switching the app icon on the Darstellung page (simulator). Against a THROWAWAY backend
/// (env TT_DEV_SERVER, TT_DEV_COOKIE, optional TT_SHOT_DIR, TT_SHOT_PREFIX).
/// Picks a motif icon, checks the selected state, switches to another one and back to the primary icon.
final class AppIconSwitchTests: XCTestCase {
    func testSwitchAppIcon() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        let prefix = env["TT_SHOT_PREFIX"] ?? "ic1"
        let app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()

        // The system confirms every icon change with an alert; dismiss it.
        addUIInterruptionMonitor(withDescription: "icon change alert") { alert in
            let ok = alert.buttons["OK"]
            if ok.exists { ok.tap(); return true }
            return false
        }

        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
        app.openSettings()
        let row = app.buttons["settings.appearance"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let primary = icon(app, "primary")
        scrollTo(primary, in: app)
        if !primary.isSelected { // the simulator keeps the icon of an earlier run
            primary.tap()
            XCTAssertTrue(waitSelected(primary, app))
        }
        shot("\(prefix)-icons-top")

        let sunset = icon(app, "TimetrackSunset")
        scrollTo(sunset, in: app)
        sunset.tap()
        XCTAssertTrue(waitSelected(sunset, app), "Feierabend Abendrot must be selected after the change")
        shot("\(prefix)-icons-sunset")

        let clock = icon(app, "TimetrackClockDark")
        scrollTo(clock, in: app)
        clock.tap()
        let switched = waitSelected(clock, app)
        shot("\(prefix)-icons-clock")
        XCTAssertTrue(switched)
        XCTAssertFalse(sunset.isSelected)

        scrollTo(primary, in: app)
        primary.tap()
        XCTAssertTrue(waitSelected(primary, app), "switching back restores the primary icon")
    }

    private func icon(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons["appearance.icon.\(name)"]
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        // Hittable is not enough: the navigation bar and the tab bar blur content that is still "hittable".
        let window = app.windows.firstMatch.frame
        func visible() -> Bool {
            element.exists && element.isHittable
                && element.frame.minY > window.minY + 140 && element.frame.maxY < window.maxY - 130
        }
        for _ in 0..<6 where !visible() { app.swipeUp() }
        for _ in 0..<12 where !visible() { app.swipeDown() }
        XCTAssertTrue(visible(), "\(element) not reachable")
    }

    private func waitSelected(_ element: XCUIElement, _ app: XCUIApplication) -> Bool {
        for _ in 0..<20 {
            if element.isSelected { return true }
            // A harmless tap on the navigation bar title lets the interruption monitor dismiss the
            // system alert ("Du hast das Symbol ... geändert").
            app.navigationBars.staticTexts.firstMatch.tap()
            usleep(500_000)
        }
        return element.isSelected
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
