import Foundation
import Testing
@testable import TimetrackCore

@Suite("Live Activity reconcile (F4)")
struct LiveActivityReconcilerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var work: LiveActivityTarget { .init(kind: .work, startedAt: start) }

    private func apply(_ plan: LiveActivityPlan, to existing: [LiveActivityExisting], canRequest: Bool = true) -> [LiveActivityExisting] {
        var result = existing.filter { !plan.end.contains($0.id) }
        if let update = plan.update, let keep = plan.keep, let index = result.firstIndex(where: { $0.id == keep }) { result[index].target = update }
        if let start = plan.start, canRequest { result.append(.init(id: "new", target: start)) }
        return result
    }

    @Test func runningTimerWithoutActivityStarts() {
        let plan = LiveActivityReconciler.plan(desired: work, existing: [])
        #expect(plan.start == work)
        #expect(plan.keep == nil && plan.end.isEmpty && plan.update == nil)
    }

    @Test func noTimerEndsEverything() {
        let existing = [LiveActivityExisting(id: "a", target: work), .init(id: "b", target: work)]
        let plan = LiveActivityReconciler.plan(desired: nil, existing: existing)
        #expect(plan.end == ["a", "b"] && plan.start == nil && plan.keep == nil)
        #expect(LiveActivityReconciler.plan(desired: nil, existing: []).isNoOp)
    }

    @Test func matchingActivityIsKept() {
        let plan = LiveActivityReconciler.plan(desired: work, existing: [.init(id: "a", target: work)])
        #expect(plan.isNoOp && plan.keep == "a")
    }

    @Test func subSecondStartNoiseIsTheSameTimer() {
        let noisy = LiveActivityTarget(kind: .work, startedAt: start.addingTimeInterval(0.4))
        let plan = LiveActivityReconciler.plan(desired: work, existing: [.init(id: "a", target: noisy)])
        #expect(plan.keep == "a" && plan.update == work && plan.start == nil && plan.end.isEmpty)
    }

    @Test func duplicatesCollapseToExactlyOne() {
        let existing = [LiveActivityExisting(id: "a", target: .init(kind: .school, startedAt: start.addingTimeInterval(-500))),
                        .init(id: "b", target: work), .init(id: "c", target: work)]
        let plan = LiveActivityReconciler.plan(desired: work, existing: existing)
        #expect(plan.keep == "b" && Set(plan.end) == ["a", "c"] && plan.update == nil && plan.start == nil)
    }

    /// A new timer (another start date) re-points the old activity: updating works in the background, requesting does not.
    @Test func staleActivityIsRepointedNotRecreated() {
        let old = LiveActivityExisting(id: "a", target: .init(kind: .work, startedAt: start.addingTimeInterval(-3600)))
        let plan = LiveActivityReconciler.plan(desired: work, existing: [old])
        #expect(plan.keep == "a" && plan.update == work && plan.start == nil)
    }

    @Test func kindChangeOfSameTimerUpdatesInPlace() {
        let plan = LiveActivityReconciler.plan(desired: .init(kind: .travel, startedAt: start), existing: [.init(id: "a", target: work)])
        #expect(plan.keep == "a" && plan.update?.kind == .travel)
    }

    /// Idempotence: applying a plan and planning again changes nothing, for every combination of desired and existing sets.
    @Test func planConvergesAndIsIdempotent() {
        let targets: [LiveActivityTarget?] = [nil, work, .init(kind: .travel, startedAt: start), .init(kind: .work, startedAt: start.addingTimeInterval(-90))]
        let sets: [[LiveActivityExisting]] = [[], [.init(id: "a", target: work)], [.init(id: "a", target: work), .init(id: "b", target: work)],
                                              [.init(id: "a", target: .init(kind: .school, startedAt: start.addingTimeInterval(-9)))]]
        for desired in targets {
            for existing in sets {
                let after = apply(LiveActivityReconciler.plan(desired: desired, existing: existing), to: existing)
                #expect(after.count == (desired == nil ? 0 : 1))
                if let desired { #expect(after.first?.target == desired) }
                #expect(LiveActivityReconciler.plan(desired: desired, existing: after).isNoOp)
            }
        }
    }

    /// Focus start in the background: the request is refused, nothing exists. The next reconcile in the foreground (the same plan
    /// again from the same snapshot) delivers it, and a Focus stop in the background ends it without any request.
    @Test func deferredStartIsCaughtUpLater() {
        var live: [LiveActivityExisting] = []
        live = apply(LiveActivityReconciler.plan(desired: work, existing: live), to: live, canRequest: false) // background: refused
        #expect(live.isEmpty)
        live = apply(LiveActivityReconciler.plan(desired: work, existing: live), to: live, canRequest: true) // foreground
        #expect(live.count == 1)
        let stopped = apply(LiveActivityReconciler.plan(desired: nil, existing: live), to: live, canRequest: false)
        #expect(stopped.isEmpty)
    }

    @Test func queueRetryAfterOfflineStartConverges() {
        // offline Focus start: nothing running, nothing shown; the queue delivers later: timer runs, one activity appears.
        var live: [LiveActivityExisting] = []
        live = apply(LiveActivityReconciler.plan(desired: nil, existing: live), to: live)
        #expect(live.isEmpty)
        live = apply(LiveActivityReconciler.plan(desired: work, existing: live), to: live)
        live = apply(LiveActivityReconciler.plan(desired: work, existing: live), to: live)
        #expect(live.count == 1)
    }

    @Test func serialGateRunsBodiesOneAtATime() async {
        let gate = SerialGate()
        let counter = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await gate.run {
                        let inside = await counter.enter()
                        try? await Task.sleep(for: .milliseconds(2))
                        await counter.leave(wasInside: inside)
                    }
                }
            }
        }
        #expect(await counter.overlaps == 0)
    }

    @Test func outcomeStoreRoundTripsAndSummaryIsGerman() {
        let suite = "test.liveactivity.\(UUID().uuidString)"
        let store = LiveActivityOutcomeStore(suiteName: suite)
        #expect(store.read() == nil)
        let outcome = LiveActivityOutcome(date: start, result: .startDeferred, source: "focus", detail: "visibility")
        store.write(outcome)
        #expect(store.read() == outcome)
        #expect(outcome.germanSummary.contains("Öffnen der App") && outcome.germanSummary.contains("focus"))
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}

private actor Counter {
    private var inside = 0
    private(set) var overlaps = 0
    func enter() -> Bool { inside += 1; if inside > 1 { overlaps += 1 }; return true }
    func leave(wasInside: Bool) { inside -= 1 }
}
