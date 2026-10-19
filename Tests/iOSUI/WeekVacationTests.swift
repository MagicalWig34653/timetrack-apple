import XCTest

/// N1a: week overview, week planner and vacation planner against the throwaway backend (skipped without TT_DEV_SERVER).
/// Screenshots go to TT_SHOT_DIR (prefix TT_SHOT_PREFIX); TT_TEXT_SIZE and TT_SHOT_SCHEME (light|dark) override the run's appearance.
final class WeekVacationTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = "n1a"

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch() throws {
        let env = ProcessInfo.processInfo.environment
        let server = try XCTUnwrap(env["TT_DEV_SERVER"], "no throwaway server configured")
        let cookie = try XCTUnwrap(env["TT_DEV_COOKIE"])
        prefix = env["TT_SHOT_PREFIX"] ?? "n1a"
        app = XCUIApplication()
        app.launchEnvironment["TT_DEV_SERVER"] = server
        app.launchEnvironment["TT_DEV_COOKIE"] = cookie
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        if let size = env["TT_TEXT_SIZE"] { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        if let scheme = env["TT_SHOT_SCHEME"] { app.launchArguments += ["-appearance.scheme", scheme] }
        app.launch()
        XCTAssertTrue(app.buttons["today.start"].waitForExistence(timeout: 20))
    }

    private func open(_ title: String, _ id: String) {
        let tab = app.tabBars.buttons[title]
        if tab.exists { tab.tap() } else { el("sidebar.\(id)").tap() }
    }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["TT_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(prefix)-\(name).png"))
    }

    /// Taps a segment (coordinate tap, retried) until `target` shows up; the plain tap is unreliable inside the iPad split view.
    private func segment(_ title: String, target: String) {
        let button = app.segmentedControls["time.segments"].buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "segment \(title)")
        for _ in 0..<4 where !el(target).exists {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = el(target).waitForExistence(timeout: 6)
        }
    }

    private func scrollTo(_ id: String) {
        for _ in 0..<6 where !el(id).isHittable { app.swipeUp() }
    }

    func testWeekOverviewAndPlanner() throws {
        try launch()
        open("Zeit", "time")
        segment("Woche", target: "week.summary")
        XCTAssertTrue(el("week.summary").waitForExistence(timeout: 15))
        sleep(1)
        shot("week-overview")
        // Previous week keeps working (navigation, reload).
        el("week.previous").tap()
        XCTAssertTrue(el("week.current").waitForExistence(timeout: 10))
        el("week.current").tap()

        segment("Planen", target: "plan.standard")
        XCTAssertTrue(el("plan.standard").waitForExistence(timeout: 15))
        sleep(1)
        shot("planner-empty")
        XCTAssertEqual(el("plan.dirty_state").label, "Alles gespeichert")
        scrollTo("plan.standard")
        el("plan.standard").tap()
        XCTAssertEqual(el("plan.dirty_state").label, "Ungespeicherte Änderungen")
        sleep(1)
        shot("planner-standard")

        // Leaving with unsaved changes asks first; "Weiter bearbeiten" keeps the draft.
        for _ in 0..<8 where !el("week.next").isHittable { app.swipeDown() }
        el("week.next").tap()
        XCTAssertTrue(app.buttons["Weiter bearbeiten"].waitForExistence(timeout: 5))
        shot("planner-leave-dialog")
        app.buttons["Weiter bearbeiten"].tap()
        XCTAssertEqual(el("plan.dirty_state").label, "Ungespeicherte Änderungen")

        el("plan.save").tap()
        for _ in 0..<30 where el("plan.dirty_state").label != "Alles gespeichert" { sleep(1) }
        XCTAssertEqual(el("plan.dirty_state").label, "Alles gespeichert")
        shot("planner-saved")

        // Overview now shows the plan next to actual time.
        segment("Woche", target: "week.summary")
        el("week.next").tap()
        sleep(2)
        shot("week-overview-planned")
    }

    func testVacationPlannerBooking() throws {
        try launch()
        open("Urlaub", "vacation")
        XCTAssertTrue(el("vacation.planner.open").waitForExistence(timeout: 15))
        el("vacation.planner.open").tap()
        XCTAssertTrue(el("vp.budget").waitForExistence(timeout: 20))
        XCTAssertTrue(el("vp.card").firstMatch.waitForExistence(timeout: 20))
        sleep(1)
        shot("vp-top")
        el("vp.filters.toggle").tap()
        sleep(1)
        shot("vp-filters")
        el("vp.filters.toggle").tap()

        let take = el("vp.take")
        for _ in 0..<4 where !take.isHittable { app.swipeUp() }
        shot("vp-card")
        take.tap()
        XCTAssertTrue(el("take.confirm").waitForExistence(timeout: 10))
        sleep(1)
        shot("vp-confirm")
        if el("take.ack_conflicts").exists { el("take.ack_conflicts").tap() }
        if el("take.ack_budget").exists { el("take.ack_budget").tap() }
        el("take.confirm").tap()
        XCTAssertTrue(el("vp.notice").waitForExistence(timeout: 15))
        shot("vp-booked")
    }
}
