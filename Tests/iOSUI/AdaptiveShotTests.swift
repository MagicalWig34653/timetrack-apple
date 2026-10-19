import XCTest

/// AD1: screenshots of every top-level section on iPad (landscape and portrait) for the before/after comparison.
/// Needs the throwaway server environment (TT_DEV_SERVER, TT_DEV_COOKIE); optional TT_SHOT_DIR, TT_SHOT_PREFIX, TT_SHOT_SCHEME (system|light|dark).
final class AdaptiveShotTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "ad1"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testSectionScreens() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "ad1"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-appearance.scheme", env["TT_SHOT_SCHEME"] ?? "system"]
        for (orientation, label) in [(UIDeviceOrientation.landscapeLeft, "land"), (.portrait, "port")] {
            XCUIDevice.shared.orientation = orientation
            app.launch()
            XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
            sleep(2)
            for section in ["today", "time", "calendar", "vacation", "settings"] {
                let sidebar = el("sidebar.\(section)")
                if sidebar.exists { sidebar.tap() }
                else if let tab = app.tabBars.buttons.allElementsBoundByIndex.first(where: { $0.identifier.contains(section) }) { tab.tap() }
                sleep(2)
                shot("\(label)-\(section)")
            }
            app.terminate()
        }
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }
}
