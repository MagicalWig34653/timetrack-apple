import Foundation
import Testing
@testable import TimetrackCore

@Suite("LA4 animated Live Activity icon")
struct LiveActivityIconTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func target(kind: SegmentKind = .work, paused: Bool = false, style: LiveActivityIconStyle? = .shovel, worked: Int = 0) -> LiveActivityTarget {
        LiveActivityTarget(kind: kind, startedAt: start, pausedAt: paused ? start : nil, workedSeconds: worked, iconStyle: style)
    }

    @Test func defaultIsOffAndConservative() {
        #expect(LiveActivityIconStyle.default == .off)
        #expect(!LiveActivityIconStyle.off.isAnimated)
        #expect(LiveActivityIconStyle.off.fontName == nil)
        #expect(LiveActivityIconStyle.shovel.fontName == "TTFramesShovel")
        #expect(LiveActivityIconStyle.briefcase.fontName == "TTFramesBriefcase")
        #expect(LiveActivityIconStyle.allCases.count == 3)
    }

    @Test func frameIsTheSecondsDigit() {
        #expect(LiveActivityIconStyle.frame(atElapsed: 0) == 0)
        #expect(LiveActivityIconStyle.frame(atElapsed: 9) == 9)
        #expect(LiveActivityIconStyle.frame(atElapsed: 10) == 0)
        #expect(LiveActivityIconStyle.frame(atElapsed: 1_234_567) == 7)
        #expect(LiveActivityIconStyle.frame(atElapsed: -3) == 7) // never traps, never negative
    }

    @Test func frameFollowsTheWorkClockAndFreezesInAPause() {
        let running = target(worked: 3_600)
        #expect(running.iconFrame(at: start.addingTimeInterval(0)) == 0)
        #expect(running.iconFrame(at: start.addingTimeInterval(4)) == 4)
        #expect(running.iconFrame(at: start.addingTimeInterval(13)) == 3)
        let paused = target(paused: true, worked: 3_605)
        #expect(paused.iconFrame(at: start.addingTimeInterval(100)) == 5)
    }

    @Test func onlyRunningWorkAnimates() {
        #expect(target().activeIconStyle == .shovel)
        #expect(target(paused: true).activeIconStyle == .off)
        #expect(target(kind: .school).activeIconStyle == .off)
        #expect(target(kind: .travel).activeIconStyle == .off)
        #expect(target(style: nil).activeIconStyle == .off)
    }

    @Test func restingFramesAreValidPoses() {
        for style in LiveActivityIconStyle.allCases { #expect((0..<LiveActivityIconStyle.frameCount).contains(style.restingFrame)) }
    }

    @Test func storeRoundTripAndUnknownValue() {
        let suite = "la4.test.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = LiveActivityIconStore(suiteName: suite)
        #expect(store.read() == .off)
        store.write(.briefcase)
        #expect(store.read() == .briefcase)
        UserDefaults(suiteName: suite)?.set("unicorn", forKey: LiveActivityIconStore.key)
        #expect(store.read() == .off)
    }

    @Test func targetDecodesWithoutStyleAndCarriesItThroughJSON() throws {
        let old = #"{"kind":"work","startedAt":0,"workedSeconds":5}"#
        let decoded = try JSONDecoder().decode(LiveActivityTarget.self, from: Data(old.utf8))
        #expect(decoded.iconStyle == nil)
        let data = try JSONEncoder().encode(target())
        #expect(try JSONDecoder().decode(LiveActivityTarget.self, from: data).iconStyle == .shovel)
    }

    @Test func styleChangeIsAnUpdateNotARestart() {
        let existing = LiveActivityExisting(id: "a", target: target(style: nil))
        let plan = LiveActivityReconciler.plan(desired: target(style: .shovel), existing: [existing])
        #expect(plan.keep == "a" && plan.update?.iconStyle == .shovel && plan.start == nil && plan.end.isEmpty)
    }

    @Test func desiredCarriesTheChosenStyleOnlyWhenAnimated() {
        let now = Date(), zone = TimeZone.current
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = zone
        let snap = WidgetSnapshot(isRunning: true, kind: .work, startedAt: now.addingTimeInterval(-60), todaySeconds: 60, day: fmt.string(from: now),
                                  timeZone: zone.identifier, updatedAt: now)
        #expect(LiveActivityTarget.desired(snapshot: snap, pause: nil, iconStyle: .briefcase, now: now)?.iconStyle == .briefcase)
        #expect(LiveActivityTarget.desired(snapshot: snap, pause: nil, iconStyle: .off, now: now)?.iconStyle == nil)
    }
}
