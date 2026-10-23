import XCTest

/// PL1: planning area (coming weeks) and plan shares against the throwaway backend (skipped without TT_DEV_SERVER).
/// The seed script creates the account "ben", who shares plan and vacation with the test account.
final class PlanningAreaTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "pl1"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "pl1"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-time.zoom", "month"]
        if let scheme = env["TT_SHOT_SCHEME"] { app.launchArguments += ["-appearance.scheme", scheme] }
        app.launch()
        XCTAssertTrue(app.startControl.waitForExistence(timeout: 20))
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }

    /// Zeit screen -> "Mehr" menu -> planning area (Z2: a fixed entry of the Zeit screen, no longer a menu inside the planner).
    private func openPlanningArea() {
        let tab = app.tabBars.buttons["Zeit"]
        if tab.exists { tab.tap() } else { el("sidebar.time").tap() }
        XCTAssertTrue(el("time.more").waitForExistence(timeout: 15))
        el("time.more").tap()
        XCTAssertTrue(el("time.planning_area").waitForExistence(timeout: 5))
        el("time.planning_area").tap()
    }

    func testComingWeeksOpenThePlanner() throws {
        try launch()
        openPlanningArea()
        XCTAssertTrue(el("planning.shares").waitForExistence(timeout: 15))
        sleep(2)
        shot("weeks")
        // The week after the current one is a row; tapping it opens the planner on that week.
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'planning.week.'"))
        XCTAssertGreaterThanOrEqual(rows.count, 4)
        rows.element(boundBy: 1).tap()
        // Z2: the week opens in the planning mode of the Zeit screen (no second planner screen is pushed).
        XCTAssertTrue(el("plan.standard").waitForExistence(timeout: 15))
        XCTAssertTrue(el("week.plan.done").waitForExistence(timeout: 10))
    }

    func testSharesCreateToggleRevokeAndIncomingView() throws {
        try launch()
        openPlanningArea()
        XCTAssertTrue(el("planning.shares").waitForExistence(timeout: 15))
        el("planning.shares").tap()
        XCTAssertTrue(el("share.create").waitForExistence(timeout: 15))
        XCTAssertTrue(el("share.out.empty").exists)
        // Incoming share from "ben" is listed.
        XCTAssertTrue(el("share.in.Ben Beispiel").waitForExistence(timeout: 10))
        // Nothing is created without a scope.
        el("share.handle").tap()
        app.typeText("ben")
        el("share.create").tap()
        XCTAssertTrue(el("share.problem").waitForExistence(timeout: 5))
        // Create with the plan scope, then switch another scope on.
        el("share.new.plan").tap()
        el("share.create").tap()
        XCTAssertTrue(el("share.ben.plan").waitForExistence(timeout: 10))
        XCTAssertFalse(el("share.out.empty").exists)
        sleep(1)
        shot("shares")
        el("share.ben.vacation").tap()
        XCTAssertEqual(el("share.ben.vacation").value as? String, "1")
        // Incoming view shows exactly the shared scopes.
        el("share.in.Ben Beispiel").tap()
        XCTAssertTrue(el("shared.load").waitForExistence(timeout: 10))
        sleep(2)
        shot("shared-view")
        XCTAssertTrue(app.staticTexts["Planung"].exists)
        XCTAssertFalse(app.staticTexts["Tatsächliche Zeiten"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // Revoke with confirmation.
        el("share.revoke.ben").tap()
        app.buttons.matching(identifier: "Widerrufen").allElementsBoundByIndex.last?.tap()
        XCTAssertTrue(el("share.out.empty").waitForExistence(timeout: 10))
    }
}
