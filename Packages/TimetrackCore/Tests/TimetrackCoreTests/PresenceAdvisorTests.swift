import Foundation
import Testing
@testable import TimetrackCore

@Suite struct PresenceAdvisorTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    let on = PresenceSettings(enabled: true)

    @Test func offByDefault() {
        var advisor = PresenceAdvisor()
        advisor.away(.locked, at: at(60))
        #expect(advisor.returned(at: at(120), timer: .running(startedAt: at(0)), atWorkPlace: true) == .none)
        #expect(PresenceSettings().enabled == false)
    }

    @Test func longAbsenceOffersToEndAtTheMomentOfLeaving() {
        var advisor = PresenceAdvisor(settings: on)
        advisor.away(.asleep, at: at(120))
        let advice = advisor.returned(at: at(600), timer: .running(startedAt: at(0)), atWorkPlace: false)
        #expect(advice == .suggestStop(endAt: at(120), away: 480 * 60, reason: .asleep))
        #expect(!advisor.isAway)
    }

    @Test func shortAbsenceAsksNothing() {
        var advisor = PresenceAdvisor(settings: on)
        advisor.away(.locked, at: at(60))
        #expect(advisor.returned(at: at(65), timer: .running(startedAt: at(0)), atWorkPlace: true) == .none)
    }

    @Test func lockThenSleepCountsFromTheLock() {
        var advisor = PresenceAdvisor(settings: on)
        advisor.away(.locked, at: at(60))
        advisor.away(.asleep, at: at(75))
        let advice = advisor.returned(at: at(200), timer: .running(startedAt: at(0)), atWorkPlace: false)
        #expect(advice == .suggestStop(endAt: at(60), away: 140 * 60, reason: .locked))
    }

    @Test func timerStartedAfterLeavingIsNeverStopped() {
        var advisor = PresenceAdvisor(settings: on)
        advisor.away(.locked, at: at(10))
        #expect(advisor.returned(at: at(100), timer: .running(startedAt: at(50)), atWorkPlace: false) == .none)
    }

    @Test func unlockAtAWorkPlaceOffersToStart() {
        var advisor = PresenceAdvisor(settings: on)
        advisor.away(.asleep, at: at(0))
        #expect(advisor.returned(at: at(600), timer: .idle, atWorkPlace: true) == .suggestStart(away: 600 * 60))
        // Not elsewhere, not after a quick lock, and not twice within the cooldown.
        advisor.away(.locked, at: at(610))
        #expect(advisor.returned(at: at(640), timer: .idle, atWorkPlace: true) == .none)
        advisor.away(.locked, at: at(700))
        #expect(advisor.returned(at: at(760), timer: .idle, atWorkPlace: false) == .none)
        advisor.away(.locked, at: at(800))
        #expect(advisor.returned(at: at(900), timer: .idle, atWorkPlace: true) == .suggestStart(away: 100 * 60))
    }

    @Test func startSuggestionCanBeSwitchedOff() {
        var advisor = PresenceAdvisor(settings: PresenceSettings(enabled: true, suggestStartAtUnlock: false))
        advisor.away(.asleep, at: at(0))
        #expect(advisor.returned(at: at(600), timer: .idle, atWorkPlace: true) == .none)
    }

    @Test func idleOffersToEndAtTheLastInputOnce() {
        var advisor = PresenceAdvisor(settings: on)
        let timer = PresenceTimer.running(startedAt: at(0))
        #expect(advisor.idle(seconds: 5 * 60, at: at(65), timer: timer) == .none)
        let first = advisor.idle(seconds: 15 * 60, at: at(75), timer: timer)
        #expect(first == .suggestStop(endAt: at(60), away: 15 * 60, reason: .idle))
        // The same idle period is not asked again at the next poll.
        #expect(advisor.idle(seconds: 16 * 60, at: at(76), timer: timer) == .none)
        // Input again, later a new idle period is asked about.
        #expect(advisor.idle(seconds: 10, at: at(90), timer: timer) == .none)
        #expect(advisor.idle(seconds: 20 * 60, at: at(120), timer: timer) == .suggestStop(endAt: at(100), away: 20 * 60, reason: .idle))
    }

    @Test func idleWithoutRunningTimerOrBeforeStartAsksNothing() {
        var advisor = PresenceAdvisor(settings: on)
        #expect(advisor.idle(seconds: 30 * 60, at: at(100), timer: .idle) == .none)
        #expect(advisor.idle(seconds: 30 * 60, at: at(100), timer: .running(startedAt: at(90))) == .none)
        var off = PresenceAdvisor(settings: PresenceSettings(enabled: true, askWhenIdle: false))
        #expect(off.idle(seconds: 30 * 60, at: at(100), timer: .running(startedAt: at(0))) == .none)
    }
}

@Suite struct RecentKindsTests {
    @Test func newestFirstWithoutDuplicates() {
        var recent = RecentKinds()
        recent.record(.work)
        recent.record(.school)
        recent.record(.work)
        #expect(recent.kinds == [.work, .school])
        #expect(recent.quickStart == [.work, .school, .travel])
        #expect(RecentKinds(rawValues: recent.rawValues) == recent)
    }

    @Test func emptyStillOffersEveryKind() {
        #expect(RecentKinds().quickStart == SegmentKind.selectable)
        #expect(RecentKinds(rawValues: "bogus,unknown,travel").kinds == [.travel])
    }
}
