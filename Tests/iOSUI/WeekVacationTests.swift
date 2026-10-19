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

    /// Z1: week details are a drill-down of the time list; the planner is pushed from the details.
    private func openWeekDetails() {
        XCTAssertTrue(el("time.week_details").waitForExistence(timeout: 15))
        el("time.week_details").tap()
    }

    private func openPlanner() {
        let button = el("week.plan")
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
    }

    private func expectDirty(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 where el("plan.dirty_state").label != label { sleep(1) }
        XCTAssertEqual(el("plan.dirty_state").label, label, file: file, line: line)
    }

    private func scrollTo(_ id: String) {
        for _ in 0..<6 where !el(id).isHittable { app.swipeUp() }
    }

    func testWeekOverviewAndPlanner() throws {
        try launch()
        open("Zeit", "time")
        openWeekDetails()
        XCTAssertTrue(el("week.summary").waitForExistence(timeout: 15))
        sleep(1)
        shot("week-overview")
        // Previous week keeps working (navigation, reload).
        el("week.previous").tap()
        XCTAssertTrue(el("week.current").waitForExistence(timeout: 10))
        el("week.current").tap()

        openPlanner()
        XCTAssertTrue(el("plan.standard").waitForExistence(timeout: 15))
        sleep(1)
        shot("planner-empty")
        expectDirty("Alles gespeichert")
        for _ in 0..<3 where el("plan.dirty_state").label != "Nicht gespeichert" {
            scrollTo("plan.standard")
            el("plan.standard").tap()
            sleep(1)
        }
        expectDirty("Nicht gespeichert")
        sleep(1)
        shot("planner-standard")

        // Leaving with unsaved changes asks first; "Weiter bearbeiten" keeps the draft.
        for _ in 0..<8 where !el("week.next").isHittable { app.swipeDown() }
        el("week.next").tap()
        XCTAssertTrue(app.buttons["Weiter bearbeiten"].waitForExistence(timeout: 5))
        shot("planner-leave-dialog")
        app.buttons["Weiter bearbeiten"].tap()
        expectDirty("Nicht gespeichert")

        el("plan.save").tap()
        for _ in 0..<30 where el("plan.dirty_state").label != "Alles gespeichert" { sleep(1) }
        XCTAssertEqual(el("plan.dirty_state").label, "Alles gespeichert")
        shot("planner-saved")

        // Overview now shows the plan next to actual time.
        app.navigationBars.buttons.element(boundBy: 0).tap() // back to the week details
        XCTAssertTrue(el("week.summary").waitForExistence(timeout: 15))
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
