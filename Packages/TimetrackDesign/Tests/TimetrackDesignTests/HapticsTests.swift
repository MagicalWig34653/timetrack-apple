import Foundation
import Testing
import TimetrackCore
@testable import TimetrackDesign

@MainActor
final class RecordingPerformer: HapticPerforming {
    private(set) var events: [TTHaptic] = []
    func perform(_ kind: TTHaptic) { events.append(kind) }
}

@MainActor
@Suite struct HapticsTests {
    /// Engine with a fake clock that advances 1 s per call unless the test pins it.
    final class Clock { var time: TimeInterval = 100 }

    func makeEngine(level: HapticLevel, clock: Clock = Clock()) -> (TTHapticEngine, RecordingPerformer, Clock) {
        let performer = RecordingPerformer()
        let engine = TTHapticEngine(performer: performer, level: { level }, now: { clock.time })
        return (engine, performer, clock)
    }

    @Test func offPlaysNothing() {
        let (engine, performer, _) = makeEngine(level: .off)
        for kind in TTHaptic.allCases { engine.play(kind) }
        #expect(performer.events.isEmpty)
    }

    @Test func normalPlaysEverythingAsIs() {
        let clock = Clock()
        let (engine, performer, _) = makeEngine(level: .normal, clock: clock)
        for kind in TTHaptic.allCases {
            engine.play(kind)
            clock.time += 1
        }
        #expect(performer.events == TTHaptic.allCases)
    }

    @Test func subtleKeepsOnlyOutcomes() {
        for kind in TTHaptic.allCases {
            let resolved = HapticPolicy.resolve(kind, level: .subtle)
            let expected: Set<TTHaptic> = [.start, .stop, .success, .warning, .error, .confirmDestructive]
            #expect((resolved != nil) == expected.contains(kind), "\(kind)")
        }
        #expect(HapticPolicy.resolve(.selection, level: .subtle) == nil)
        #expect(HapticPolicy.resolve(.softTap, level: .subtle) == nil)
    }

    @Test func debounceDropsSecondHapticWithin80ms() {
        let (engine, performer, clock) = makeEngine(level: .normal)
        engine.play(.selection)
        clock.time += 0.05
        engine.play(.success) // dropped
        clock.time += 0.04 // 90 ms after the first
        engine.play(.success)
        #expect(performer.events == [.selection, .success])
    }

    @Test func droppedHapticsDoNotMoveTheDebounceWindow() {
        let (engine, performer, clock) = makeEngine(level: .off)
        engine.play(.success)
        clock.time += 0.01
        #expect(performer.events.isEmpty)
        #expect(engine.admit(.success) == nil)
    }

    @Test func storedLevelDefaultsToNormalAndIgnoresGarbage() {
        let defaults = UserDefaults(suiteName: "haptics-test-\(UUID().uuidString)")!
        #expect(HapticLevel.stored(in: defaults) == .normal)
        defaults.set("subtle", forKey: HapticLevel.storageKey)
        #expect(HapticLevel.stored(in: defaults) == .subtle)
        defaults.set("loud", forKey: HapticLevel.storageKey)
        #expect(HapticLevel.stored(in: defaults) == .normal)
        #expect(HapticLevel.storageKey == "appearance.haptics")
    }

    @Test func outcomesMapToHaptics() {
        #expect(HapticPolicy.haptic(for: .timerStarted) == .start)
        #expect(HapticPolicy.haptic(for: .timerStopped) == .stop)
        #expect(HapticPolicy.haptic(for: .saved) == .success)
        #expect(HapticPolicy.haptic(for: .deleted) == .success)
        #expect(HapticPolicy.haptic(for: .failed) == .error)
    }

    @Test func everyKindHasSensoryFeedback() {
        for kind in TTHaptic.allCases { _ = kind.sensoryFeedback }
    }
}

@Suite struct HapticsToggleTests {
    @Test func switchMapsToLevels() {
        #expect(HapticsToggle.isOn("normal") && HapticsToggle.isOn("subtle") && !HapticsToggle.isOn("off"))
        #expect(HapticsToggle.isOn("garbage"), "unknown values mean the default (on)")
        #expect(HapticsToggle.level(isOn: false, current: "normal") == "off")
        #expect(HapticsToggle.level(isOn: true, current: "off") == "normal")
        #expect(HapticsToggle.level(isOn: true, current: "subtle") == "subtle", "switching on keeps a finer level")
    }
}
