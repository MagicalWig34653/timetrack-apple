import Foundation
import Testing
@testable import TimetrackCore

/// LA2: crash hunt. SwiftUI traps on `Text(timerInterval:)` / `ProgressView(timerInterval:)` ranges whose end precedes their start and
/// `Int(Double)` traps on NaN/infinity, so every range and conversion the Live Activity views use is checked against hostile states.
@Suite("Live Activity robustness (LA2)")
struct LiveActivityRobustnessTests {
    let base = Date(timeIntervalSince1970: 1_792_400_000)

    func assertValid(_ target: LiveActivityTarget, at date: Date, sourceLocation: SourceLocation = #_sourceLocation) {
        let clock = target.clock
        #expect(clock.range.lowerBound <= clock.range.upperBound, sourceLocation: sourceLocation)
        if let pause = clock.pauseTime { #expect(clock.range.contains(pause), sourceLocation: sourceLocation) }
        if let interval = target.progressInterval { #expect(interval.lowerBound < interval.upperBound, sourceLocation: sourceLocation) }
        if let fraction = target.fraction(at: date) { #expect(fraction.isFinite && (0...1).contains(fraction), sourceLocation: sourceLocation) }
        #expect(target.workedSeconds(at: date) >= 0, sourceLocation: sourceLocation)
        _ = target.end(at: date)
    }

    @Test func negativeOrAbsurdContentStateNeverProducesAnInvertedRange() {
        for worked in [-1, -86_400, 0, 1, 86_400, 1_000_000_000, Int.max, Int.min] {
            for paused in [false, true] {
                for planned in [nil, -5, 0, 1, 28_800, 1_000_000_000, Int.max] as [Int?] {
                    let target = LiveActivityTarget(kind: .work, startedAt: base, pausedAt: paused ? base : nil, workedSeconds: worked,
                                                    plannedSeconds: planned, plannedEnd: base.addingTimeInterval(-3_600), dayStart: base)
                    if (planned ?? 0) > 1_000_000_000 { continue } // beyond any real day (Double loses the second); see wholeSeconds
                    assertValid(target, at: base.addingTimeInterval(60))
                }
            }
        }
    }

    @Test func hostileDatesDoNotTrap() {
        let dates: [Date] = [.distantPast, .distantFuture, base, Date(timeIntervalSinceReferenceDate: .nan)]
        for start in dates { for end in dates + [nil as Date?].compactMap { $0 } {
            for first in dates {
                let target = LiveActivityTarget(kind: .travel, startedAt: start, workedSeconds: 600, plannedSeconds: 28_800, plannedEnd: end, dayStart: first)
                for now in [base, .distantFuture] { _ = target.fraction(at: now); _ = target.workedSeconds(at: now); _ = target.end(at: now) }
                if start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite {
                    #expect(target.clock.range.lowerBound <= target.clock.range.upperBound || !first.timeIntervalSinceReferenceDate.isFinite)
                }
            }
        } }
    }

    @Test func wholeSecondsIsTotal() {
        #expect(LiveActivityTarget.wholeSeconds(.nan) == 0 && LiveActivityTarget.wholeSeconds(.infinity) == 0)
        #expect(LiveActivityTarget.wholeSeconds(-5) == 0 && LiveActivityTarget.wholeSeconds(90.9) == 90)
        #expect(LiveActivityTarget.wholeSeconds(1e30) == 4_000_000_000)
    }

    /// Rapid, random Start/Pause/Weiter/Stopp presses (also at the same instant and with the clock stepping backwards), applied like
    /// `TimerControlRunner` does. Whatever happens, the activity state stays drawable and consistent.
    @Test func rapidRandomPressesKeepTheStateValid() {
        var generator = SeededGenerator(seed: 42)
        var snapshot: WidgetSnapshot? = WidgetSnapshot(isRunning: false, kind: .work, startedAt: nil, todaySeconds: 3_600, day: "2026-10-19",
                                                       timeZone: "UTC", updatedAt: base, targetSeconds: 28_800, plannedEnd: base.addingTimeInterval(36_000),
                                                       plannedSeconds: 28_800)
        var marker: PauseMarker?
        var now = base
        let actions: [TimerControlAction] = [.start, .pause, .resume, .stop]
        var applied = 0
        for _ in 0..<5_000 {
            now = now.addingTimeInterval(Double.random(in: -30...90, using: &generator)) // may go backwards
            let action = actions.randomElement(using: &generator)!
            let plan = TimerPress.plan(action, snapshot: snapshot, marker: marker, now: now)
            switch plan.marker {
            case .keep: break
            case .set(let value): marker = value
            case .clear: marker = nil
            }
            if let next = plan.snapshot { snapshot = next; applied += 1 }
            #expect((snapshot?.todaySeconds ?? 0) >= 0)
            if let target = LiveActivityTarget.desired(snapshot: snapshot, pause: marker, now: now) {
                assertValid(target, at: now)
                #expect(target.isPaused != (snapshot?.isRunning == true))
            } else {
                #expect(snapshot?.isRunning != true)
            }
        }
        #expect(applied > 1_000)
    }

    @Test func reconcilerIsIdempotentForAnyCurrentActivity() {
        let a = LiveActivityTarget(kind: .work, startedAt: base, workedSeconds: 10)
        let b = LiveActivityTarget(kind: .work, startedAt: base.addingTimeInterval(5), pausedAt: base.addingTimeInterval(5), workedSeconds: 10)
        for desired in [nil, a, b] as [LiveActivityTarget?] {
            for existing in [[], [a], [b], [a, b], [b, a, a]] as [[LiveActivityTarget]] {
                let alive = existing.enumerated().map { LiveActivityExisting(id: "\($0.offset)", target: $0.element) }
                let plan = LiveActivityReconciler.plan(desired: desired, existing: alive)
                #expect(plan.start == nil || alive.isEmpty) // never requests while one lives (request fails in the background)
                if desired == nil { #expect(plan.end.count == alive.count) } else if !alive.isEmpty { #expect(plan.keep != nil && plan.end.count == alive.count - 1) }
            }
        }
    }

    /// Concurrent reconciles (app model sync, Focus callback, foreground, intent) must run one at a time.
    @Test func serialGateNeverRunsTwoBodiesAtOnce() async {
        let gate = SerialGate()
        let counter = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask { await gate.run { await counter.enter(); await Task.yield(); await counter.leave() } }
            }
        }
        let (maxInside, total) = await (counter.maxInside, counter.total)
        #expect(maxInside == 1 && total == 200)
    }
}

private actor Counter {
    var inside = 0, maxInside = 0, total = 0
    func enter() { inside += 1; total += 1; maxInside = max(maxInside, inside) }
    func leave() { inside -= 1 }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
