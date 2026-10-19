import Foundation
import Testing
@testable import TimetrackCore

@Suite struct OverworkNotificationTests {
    let zone = TimeZone(identifier: "Europe/Berlin")!
    var calendar: DayCalendar { DayCalendar(timeZone: zone) }
    let all = OverworkSettings(plannedEnd: true, dailyLimits: true, missingBreak: true)

    func at(_ day: LocalDay, _ hour: Int, _ minute: Int = 0) -> Date { calendar.instant(day: day, hour: hour, minute: minute)! }

    /// Running work timer started at `start`, with `done` seconds finished before it and the given earlier segments.
    func snapshot(day: LocalDay = "2026-10-19", start: Date, done: Int = 0, plannedEnd: Date? = nil, earlier: [(Date, Date)] = [],
                  kind: SegmentKind = .work, running: Bool = true) -> WidgetSnapshot {
        var segments = earlier.map { WidgetSegment(kind: .work, startedAt: $0.0, endedAt: $0.1) }
        if running { segments.append(WidgetSegment(kind: kind, startedAt: start, endedAt: nil)) }
        return WidgetSnapshot(isRunning: running, kind: kind, startedAt: running ? start : nil, todaySeconds: done, day: day, timeZone: zone.identifier,
                              updatedAt: start, segments: segments, plannedEnd: plannedEnd, firstStart: segments.first?.startedAt)
    }

    func fire(_ items: [OverworkItem], _ kind: OverworkKind) -> Date? { items.first { $0.kind == kind }?.fireDate }

    @Test func defaultsAreOff() {
        #expect(OverworkSettings().isAnyEnabled == false)
        let day = "2026-10-19"
        #expect(OverworkPlanner.plan(snapshot: snapshot(start: at(day, 8)), settings: OverworkSettings(), now: at(day, 8)).isEmpty)
    }

    @Test func plansAllTypesFromAFreshStart() {
        let start = at("2026-10-19", 8)
        let items = OverworkPlanner.plan(snapshot: snapshot(start: start, plannedEnd: at("2026-10-19", 16, 30)), settings: all, now: start)
        #expect(items.map(\.kind) == [.breakAfter6, .plannedEnd, .regularLimitWarning, .regularLimit, .breakAfter9, .maximumLimitWarning, .maximumLimit]
            .sorted { fire(items, $0)! < fire(items, $1)! })
        #expect(fire(items, .regularLimitWarning) == start.addingTimeInterval(7.5 * 3600))
        #expect(fire(items, .regularLimit) == start.addingTimeInterval(8 * 3600))
        #expect(fire(items, .maximumLimit) == start.addingTimeInterval(10 * 3600))
        #expect(fire(items, .breakAfter6) == start.addingTimeInterval(6 * 3600))
        #expect(fire(items, .plannedEnd) == at("2026-10-19", 16, 30))
        #expect(items.first { $0.kind == .regularLimit }?.id == "de.linolaske.timetrack.overwork.regularLimit")
    }

    @Test func eachTypeIsSwitchedSeparately() {
        let start = at("2026-10-19", 8)
        let snap = snapshot(start: start, plannedEnd: at("2026-10-19", 16))
        #expect(OverworkPlanner.plan(snapshot: snap, settings: OverworkSettings(plannedEnd: true), now: start).map(\.kind) == [.plannedEnd])
        #expect(Set(OverworkPlanner.plan(snapshot: snap, settings: OverworkSettings(dailyLimits: true), now: start).map(\.kind))
            == [.regularLimitWarning, .regularLimit, .maximumLimitWarning, .maximumLimit])
        #expect(Set(OverworkPlanner.plan(snapshot: snap, settings: OverworkSettings(missingBreak: true), now: start).map(\.kind)) == [.breakAfter6, .breakAfter9])
    }

    @Test func finishedWorkMovesTheInstantsEarlier() {
        let start = at("2026-10-19", 13)
        let items = OverworkPlanner.plan(snapshot: snapshot(start: start, done: 4 * 3600), settings: OverworkSettings(dailyLimits: true), now: start)
        #expect(fire(items, .regularLimit) == start.addingTimeInterval(4 * 3600))
    }

    @Test func pauseAndResumeShiftTheInstantsByThePause() {
        let morning = at("2026-10-19", 8)
        let before = OverworkPlanner.plan(snapshot: snapshot(start: morning), settings: OverworkSettings(dailyLimits: true), now: morning)
        // paused 12:00-12:45: finished 4 h, new segment starts 12:45 => 8 h after 16:45 instead of 16:00
        let resume = at("2026-10-19", 12, 45)
        let after = OverworkPlanner.plan(snapshot: snapshot(start: resume, done: 4 * 3600, earlier: [(morning, at("2026-10-19", 12))]),
                                         settings: OverworkSettings(dailyLimits: true), now: resume)
        #expect(fire(before, .regularLimit) == at("2026-10-19", 16))
        #expect(fire(after, .regularLimit) == at("2026-10-19", 16, 45))
    }

    @Test func pausedOrStoppedPlansNothingSoPendingOnesAreRemoved() {
        let now = at("2026-10-19", 12)
        let paused = snapshot(start: at("2026-10-19", 8), done: 4 * 3600, plannedEnd: at("2026-10-19", 17), running: false)
        let planned = OverworkPlanner.plan(snapshot: paused, settings: all, now: now)
        #expect(planned.isEmpty)
        let pending = [OverworkItem.idPrefix + "regularLimit", "foreign.id"]
        let result = OverworkPlanner.reconcile(pendingIDs: pending, planned: planned)
        #expect(result.remove == [OverworkItem.idPrefix + "regularLimit"] && result.add.isEmpty)
    }

    @Test func travelOrSchoolTimerPlansNothing() {
        let start = at("2026-10-19", 8)
        #expect(OverworkPlanner.plan(snapshot: snapshot(start: start, kind: .travel), settings: all, now: start).isEmpty)
        #expect(OverworkPlanner.plan(snapshot: snapshot(start: start, kind: .school), settings: all, now: start).isEmpty)
    }

    @Test func exceededLimitsAreNotScheduledAgain() {
        let start = at("2026-10-19", 8)
        let now = at("2026-10-19", 17) // 9 h worked
        let items = OverworkPlanner.plan(snapshot: snapshot(start: start, plannedEnd: at("2026-10-19", 16)), settings: all, now: now)
        #expect(items.map(\.kind).contains(.regularLimit) == false && items.map(\.kind).contains(.regularLimitWarning) == false)
        #expect(items.map(\.kind).contains(.plannedEnd) == false && items.map(\.kind).contains(.breakAfter6) == false)
        #expect(items.allSatisfy { $0.fireDate > now })
        #expect(Set(items.map(\.kind)) == [.maximumLimitWarning, .maximumLimit]) // the 9 h hint falls exactly on `now`: not in the future
        let late = OverworkPlanner.plan(snapshot: snapshot(start: start), settings: all, now: at("2026-10-19", 19))
        #expect(late.isEmpty)
    }

    @Test func rescheduleIsIdempotentAndKeepsIDs() {
        let start = at("2026-10-19", 8)
        let snap = snapshot(start: start, plannedEnd: at("2026-10-19", 16, 30))
        let first = OverworkPlanner.plan(snapshot: snap, settings: all, now: start)
        let second = OverworkPlanner.plan(snapshot: snap, settings: all, now: start.addingTimeInterval(60))
        #expect(first == second)
        #expect(OverworkPlanner.reconcile(pendingIDs: first.map(\.id), planned: second).remove.isEmpty)
    }

    @Test func breaksCountOnlyWhenTakenAndLongEnough() {
        let day = "2026-10-19"
        let a = at(day, 8), b = at(day, 11, 0), c = at(day, 11, 20), d = at(day, 13), e = at(day, 13, 10), f = at(day, 15, 0)
        // 20 min break counts, 10 min part does not => 20 min < 30: hint at 6 h, and at 9 h
        let items = OverworkPlanner.plan(snapshot: snapshot(start: f, done: 5 * 3600 - 600, earlier: [(a, b), (c, d), (e, f)]), settings: OverworkSettings(missingBreak: true), now: f)
        #expect(OverworkPlanner.takenBreakSeconds(snapshot: snapshot(start: f, earlier: [(a, b), (c, d), (e, f)]), started: f) == 20 * 60)
        #expect(items.first { $0.kind == .breakAfter6 }?.body == "Nach 6 Stunden Arbeit sind 30 Minuten Pause vorgesehen. Bisher erfasst: 20 Min.")
    }

    @Test func enoughBreakSuppressesTheSixHourHintButNotTheNineHourOne() {
        let day = "2026-10-19"
        let a = at(day, 8), b = at(day, 12), c = at(day, 12, 30)
        let snap = snapshot(start: c, done: 4 * 3600, earlier: [(a, b)])
        let items = OverworkPlanner.plan(snapshot: snap, settings: OverworkSettings(missingBreak: true), now: c)
        #expect(items.map(\.kind) == [.breakAfter9]) // 30 min taken: enough for 6 h, not for 9 h
        let long = snapshot(start: at(day, 13), done: 4 * 3600, earlier: [(a, b)])
        #expect(OverworkPlanner.plan(snapshot: long, settings: OverworkSettings(missingBreak: true), now: at(day, 13)).isEmpty)
    }

    @Test func noInventedBreakFromTheGapBeforeTheFirstSegment() {
        let start = at("2026-10-19", 9)
        #expect(OverworkPlanner.takenBreakSeconds(snapshot: snapshot(start: start), started: start) == 0)
    }

    @Test func instantsPastLocalMidnightAreDropped() {
        let start = at("2026-10-19", 18)
        let items = OverworkPlanner.plan(snapshot: snapshot(start: start, plannedEnd: at("2026-10-19", 23, 30)), settings: all, now: start)
        // 6 h after 18:00 = midnight exactly (not before the day end): dropped, 7.5 h and later too; the planned end 23:30 stays
        #expect(items.map(\.kind) == [.plannedEnd])
    }

    @Test func snapshotOfAnotherDayPlansNothing() {
        let start = at("2026-10-18", 20)
        #expect(OverworkPlanner.plan(snapshot: snapshot(day: "2026-10-18", start: start), settings: all, now: at("2026-10-19", 1)).isEmpty)
    }

    @Test func fallBackDayUsesElapsedTimeNotWallClock() {
        // 2026-10-25 has 25 hours in Berlin. Start 01:00 CEST (first pass); 8 h elapsed is 08:00 CET wall clock (nine wall-clock hours later would be wrong).
        let start = Date(timeIntervalSince1970: calendar.interval(of: "2026-10-25")!.start.timeIntervalSince1970 + 3600)
        let items = OverworkPlanner.plan(snapshot: snapshot(day: "2026-10-25", start: start), settings: OverworkSettings(dailyLimits: true), now: start)
        #expect(fire(items, .regularLimit) == start.addingTimeInterval(8 * 3600))
        #expect(calendar.hourAndMinute(of: fire(items, .regularLimit)!) == (8, 0))
    }

    @Test func springForwardDayPlannedEndIsTheAbsoluteInstant() {
        // 2026-03-29 has 23 hours. Start 01:00 CET; 8 h elapsed is 10:00 CEST on the wall clock (not 09:00).
        let start = at("2026-03-29", 1)
        let items = OverworkPlanner.plan(snapshot: snapshot(day: "2026-03-29", start: start, plannedEnd: at("2026-03-29", 14, 0)), settings: all, now: start)
        #expect(fire(items, .plannedEnd) == at("2026-03-29", 14, 0))
        #expect(calendar.hourAndMinute(of: fire(items, .regularLimit)!) == (10, 0))
    }

    @Test func textsAreGermanAndFactual() {
        let start = at("2026-10-19", 8)
        let items = OverworkPlanner.plan(snapshot: snapshot(start: start, plannedEnd: at("2026-10-19", 16, 30)), settings: all, now: start)
        #expect(items.first { $0.kind == .plannedEnd }?.body == "Laut Plan ist um 16:30 Uhr Feierabend. Die Zeiterfassung läuft noch.")
        #expect(items.first { $0.kind == .maximumLimit }?.title == "10 Stunden erreicht")
        #expect(items.first { $0.kind == .breakAfter6 }?.body.hasSuffix("Bisher erfasst: keine.") == true)
    }

    @Test func settingsRoundTripThroughTheStore() {
        let store = OverworkSettingsStore(suiteName: "ot1.test.\(UUID().uuidString)")
        #expect(store.read() == OverworkSettings())
        store.write(OverworkSettings(plannedEnd: true, dailyLimits: false, missingBreak: true))
        #expect(store.read() == OverworkSettings(plannedEnd: true, dailyLimits: false, missingBreak: true))
    }
}
