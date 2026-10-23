import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

@Suite struct ActivityRecorderTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    let xcode = ForegroundApp(bundleID: "com.apple.dt.Xcode", appName: "Xcode", windowTitle: "Timetrack - TodayView.swift")
    let safari = ForegroundApp(bundleID: "com.apple.Safari", appName: "Safari", windowTitle: "Bank")
    let on = ActivitySettings(enabled: true)
    let running = ActivityContext(timerRunning: true)

    @Test func everythingIsOffByDefault() {
        let defaults = ActivitySettings()
        #expect(defaults.enabled == false)
        #expect(defaults.recordWindowTitles == false)
        #expect(defaults.onlyWhileTimerRuns)
        #expect(defaults.retentionDays == 14)
        var recorder = ActivityRecorder()
        _ = recorder.update(foreground: xcode, at: at(0), context: running, settings: defaults)
        #expect(recorder.open == nil)
    }

    @Test func recordsAppSwitchesAsIntervals() {
        var recorder = ActivityRecorder()
        #expect(recorder.update(foreground: xcode, at: at(0), context: running, settings: on).isEmpty)
        let closed = recorder.update(foreground: safari, at: at(10), context: running, settings: on)
        #expect(closed.count == 1)
        #expect(closed[0].bundleID == "com.apple.dt.Xcode")
        #expect(closed[0].duration == 600)
        #expect(recorder.open?.bundleID == "com.apple.Safari")
    }

    @Test func noTitlesUnlessAsked() {
        var recorder = ActivityRecorder()
        _ = recorder.update(foreground: xcode, at: at(0), context: running, settings: on)
        let closed = recorder.finish(at: at(5))
        #expect(closed.first?.windowTitle == nil)

        var withTitles = on
        withTitles.recordWindowTitles = true
        var second = ActivityRecorder()
        _ = second.update(foreground: xcode, at: at(0), context: running, settings: withTitles)
        #expect(second.finish(at: at(5)).first?.windowTitle == "Timetrack - TodayView.swift")
    }

    @Test func titleChangeStartsANewIntervalOnlyWithTitles() {
        var withTitles = on
        withTitles.recordWindowTitles = true
        var recorder = ActivityRecorder()
        _ = recorder.update(foreground: xcode, at: at(0), context: running, settings: withTitles)
        var other = xcode
        other.windowTitle = "Other.swift"
        #expect(recorder.update(foreground: other, at: at(5), context: running, settings: withTitles).count == 1)

        var plain = ActivityRecorder()
        _ = plain.update(foreground: xcode, at: at(0), context: running, settings: on)
        #expect(plain.update(foreground: other, at: at(5), context: running, settings: on).isEmpty) // same app, titles off: still one interval
    }

    @Test func onlyWhileTheTimerRunsByDefault() {
        var recorder = ActivityRecorder()
        _ = recorder.update(foreground: xcode, at: at(0), context: ActivityContext(timerRunning: false), settings: on)
        #expect(recorder.open == nil)
        var always = on
        always.onlyWhileTimerRuns = false
        _ = recorder.update(foreground: xcode, at: at(0), context: ActivityContext(timerRunning: false), settings: always)
        #expect(recorder.open != nil)
    }

    @Test func stoppingTheTimerClosesTheInterval() {
        var recorder = ActivityRecorder()
        _ = recorder.update(foreground: xcode, at: at(0), context: running, settings: on)
        let closed = recorder.update(foreground: xcode, at: at(30), context: ActivityContext(timerRunning: false), settings: on)
        #expect(closed.first?.duration == 1800)
        #expect(recorder.open == nil)
    }

    @Test func lockSleepAndIdleStopRecording() {
        for context in [ActivityContext(timerRunning: true, screenLocked: true), ActivityContext(timerRunning: true, asleep: true),
                        ActivityContext(timerRunning: true, idle: true)] {
            var recorder = ActivityRecorder()
            _ = recorder.update(foreground: xcode, at: at(0), context: running, settings: on)
            #expect(recorder.update(foreground: xcode, at: at(20), context: context, settings: on).count == 1)
            #expect(recorder.open == nil)
        }
    }

    @Test func pausedAndExcludedAppsAreNeverRecorded() {
        var paused = on
        paused.paused = true
        var recorder = ActivityRecorder()
        _ = recorder.update(foreground: xcode, at: at(0), context: running, settings: paused)
        #expect(recorder.open == nil)

        var excluded = on
        excluded.excludedBundleIDs = ["com.apple.Safari"]
        _ = recorder.update(foreground: safari, at: at(0), context: running, settings: excluded)
        #expect(recorder.open == nil)
        _ = recorder.update(foreground: xcode, at: at(0), context: running, settings: excluded)
        #expect(recorder.open != nil)
        // Switching to the excluded app closes the previous interval and records nothing for the excluded one.
        #expect(recorder.update(foreground: safari, at: at(10), context: running, settings: excluded).count == 1)
        #expect(recorder.open == nil)
    }

    @Test func veryShortStopsAreDropped() {
        var recorder = ActivityRecorder()
        _ = recorder.update(foreground: xcode, at: at(0), context: running, settings: on)
        #expect(recorder.update(foreground: safari, at: base.addingTimeInterval(2), context: running, settings: on).isEmpty)
    }

    @Test func checkpointKeepsTheIntervalOpen() {
        var recorder = ActivityRecorder()
        _ = recorder.update(foreground: xcode, at: at(0), context: running, settings: on)
        let saved = recorder.checkpoint(at: at(1))
        #expect(saved.first?.duration == 60)
        #expect(recorder.open?.start == at(1))
    }
}

@Suite struct ActivityLogTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func interval(_ app: String, _ from: Double, _ to: Double, title: String? = nil) -> ActivityInterval {
        ActivityInterval(bundleID: app, appName: app, start: base.addingTimeInterval(from * 60), end: base.addingTimeInterval(to * 60), windowTitle: title)
    }

    @Test func checkpointsOfTheSameAppMerge() {
        var log = ActivityLog()
        log.append(interval("a", 0, 1))
        log.append(interval("a", 1, 2))
        log.append(interval("b", 2, 3))
        log.append(interval("a", 3, 4))
        #expect(log.intervals.map(\.bundleID) == ["a", "b", "a"])
        #expect(log.intervals[0].duration == 120)
    }

    @Test func retentionDeletesOldIntervals() {
        var log = ActivityLog(intervals: [interval("old", -20 * 24 * 60, -20 * 24 * 60 + 30), interval("fresh", -60, -30)])
        #expect(log.prune(retentionDays: 14, now: base) == 1)
        #expect(log.intervals.map(\.bundleID) == ["fresh"])
        #expect(log.prune(retentionDays: 14, now: base) == 0)
    }

    @Test func removeByAppAndStripTitles() {
        var log = ActivityLog(intervals: [interval("a", 0, 10, title: "x"), interval("b", 10, 20, title: "y")])
        log.stripTitles()
        #expect(log.intervals.allSatisfy { $0.windowTitle == nil })
        #expect(log.remove(bundleID: "a") == 1)
        #expect(log.intervals.map(\.bundleID) == ["b"])
    }

    @Test func clippingAndTotals() {
        let log = ActivityLog(intervals: [interval("a", 0, 30), interval("b", 30, 40), interval("a", 40, 50)])
        let clipped = log.intervals(from: base.addingTimeInterval(20 * 60), to: base.addingTimeInterval(45 * 60))
        #expect(clipped.map(\.duration) == [600, 600, 300])
        let totals = ActivitySummary.totals(log.intervals)
        #expect(totals.map(\.bundleID) == ["a", "b"])
        #expect(totals[0].seconds == 2400)
    }
}

@Suite struct ActivitySuggestionTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    func interval(_ app: String, _ from: Double, _ to: Double) -> ActivityInterval { ActivityInterval(bundleID: app, appName: app, start: at(from), end: at(to)) }
    func segment(_ from: Double, _ to: Double?, kind: SegmentKind = .work, note: String? = nil) -> Segment {
        Segment(id: UUID(), kind: kind, startedAt: at(from), endedAt: to.map(at), note: note)
    }
    let project = ActivityRule(bundleID: "xcode", appName: "xcode", labelType: .project, label: "Timetrack")

    @Test func noRuleNoSuggestion() {
        #expect(ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 60)], rules: [], segments: [segment(0, 60)]).isEmpty)
        #expect(ActivitySuggestionEngine.suggestions(intervals: [interval("mail", 0, 60)], rules: [project], segments: [segment(0, 60)]).isEmpty)
        #expect(ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 60)], rules: [ActivityRule(bundleID: "xcode", appName: "x")], segments: [segment(0, 60)]).isEmpty)
    }

    @Test func proposesALabelAsEditableNote() {
        let result = ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 60)], rules: [project], segments: [segment(0, 120)])
        #expect(result.count == 1)
        #expect(result[0].proposedNote == "Projekt: Timetrack")
        #expect(result[0].proposedKind == nil) // the rule has no kind
        #expect(result[0].seconds == 3600)
    }

    @Test func appendsToAnExistingNoteAndSkipsWhatIsAlreadyThere() {
        let existing = segment(0, 120, note: "Sprint")
        let one = ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 60)], rules: [project], segments: [existing])
        #expect(one.first?.proposedNote == "Sprint · Projekt: Timetrack")
        let done = segment(0, 120, note: "Projekt: Timetrack")
        #expect(ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 60)], rules: [project], segments: [done]).isEmpty)
    }

    @Test func mergesNeighbouringIntervalsOfTheSameTarget() {
        let terminal = ActivityRule(bundleID: "terminal", appName: "terminal", labelType: .project, label: "Timetrack")
        let result = ActivitySuggestionEngine.suggestions(
            intervals: [interval("xcode", 0, 20), interval("terminal", 20, 30), interval("xcode", 31, 45)], rules: [project, terminal], segments: [segment(0, 120)])
        #expect(result.count == 1)
        #expect(result[0].seconds == 45 * 60 - 60)
        #expect(Set(result[0].appNames) == ["xcode", "terminal"])
    }

    @Test func differentTargetsAreSeparateBlocks() {
        let school = ActivityRule(bundleID: "pages", appName: "pages", labelType: .learningField, label: "LF 5")
        let result = ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 30), interval("pages", 30, 60)], rules: [project, school], segments: [segment(0, 120)])
        #expect(result.map(\.proposedNote) == ["Projekt: Timetrack", "Lernfeld: LF 5"])
    }

    @Test func shortBlocksAreIgnored() {
        #expect(ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 4)], rules: [project], segments: [segment(0, 60)]).isEmpty)
    }

    @Test func intervalsOutsideEntriesDoNotCount() {
        // Xcode was in front for an hour, but the entry only covers the last 3 minutes of it.
        #expect(ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 60)], rules: [project], segments: [segment(57, 90)]).isEmpty)
        // A voided entry gets nothing.
        let voided = Segment(id: UUID(), kind: .work, startedAt: at(0), endedAt: at(60), voided: true)
        #expect(ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 60)], rules: [project], segments: [voided]).isEmpty)
    }

    @Test func kindIsOnlyProposedWhenTheBlockCoversTheEntry() {
        let school = ActivityRule(bundleID: "pages", appName: "pages", kind: .school)
        let whole = ActivitySuggestionEngine.suggestions(intervals: [interval("pages", 0, 58)], rules: [school], segments: [segment(0, 60)])
        #expect(whole.first?.proposedKind == .school)
        #expect(ActivitySuggestionEngine.suggestions(intervals: [interval("pages", 0, 20)], rules: [school], segments: [segment(0, 60)]).isEmpty)
        // Entry already has that kind and no label: nothing to propose.
        #expect(ActivitySuggestionEngine.suggestions(intervals: [interval("pages", 0, 58)], rules: [school], segments: [segment(0, 60, kind: .school)]).isEmpty)
    }

    @Test func dismissedSuggestionsStayGone() {
        let first = ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 60)], rules: [project], segments: [segment(0, 120)])
        let again = ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 60)], rules: [project], segments: [segment(0, 120)], dismissed: [first[0].id])
        #expect(again.isEmpty)
    }

    @Test func runningEntryUsesNow() {
        let result = ActivitySuggestionEngine.suggestions(intervals: [interval("xcode", 0, 50)], rules: [project], segments: [segment(0, nil)], now: at(55))
        #expect(result.count == 1)
    }
}

@MainActor
@Suite struct ActivityStoreTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func interval(_ app: String, ago minutes: Double, length: Double = 10, title: String? = nil) -> ActivityInterval {
        ActivityInterval(bundleID: app, appName: app, start: now.addingTimeInterval(-minutes * 60), end: now.addingTimeInterval((-minutes + length) * 60), windowTitle: title)
    }

    @Test func persistsAcrossInstances() {
        let storage = ActivityStorage.inMemory()
        let store = ActivityStore(storage: storage)
        store.update { $0.enabled = true; $0.retentionDays = 30 }
        store.record([interval("a", ago: 60)], now: now)
        store.saveRule(ActivityRule(bundleID: "a", appName: "a", labelType: .project, label: "P"))
        let again = ActivityStore(storage: storage)
        #expect(again.settings.enabled && again.settings.retentionDays == 30)
        #expect(again.log.intervals.count == 1)
        #expect(again.rules.count == 1)
    }

    @Test func deleteAllRemovesDataButKeepsSettingsAndRules() {
        let store = ActivityStore(storage: .inMemory())
        store.update { $0.enabled = true }
        store.saveRule(ActivityRule(bundleID: "a", appName: "a", label: "P"))
        store.record([interval("a", ago: 60)], now: now)
        store.dismiss("x")
        store.deleteAllData()
        #expect(store.log.isEmpty && store.dismissed.isEmpty)
        #expect(store.settings.enabled && store.rules.count == 1)
    }

    @Test func excludingForgetsRecordedData() {
        let store = ActivityStore(storage: .inMemory())
        store.record([interval("a", ago: 60), interval("b", ago: 40)], now: now)
        store.exclude(bundleID: "a")
        #expect(store.log.intervals.map(\.bundleID) == ["b"])
        store.record([interval("a", ago: 20)], now: now)
        #expect(store.log.intervals.map(\.bundleID) == ["b"])
        store.include(bundleID: "a")
        #expect(store.settings.excludedBundleIDs.isEmpty)
    }

    @Test func retentionAppliesWhenRecordingAndWhenShortened() {
        let store = ActivityStore(storage: .inMemory())
        store.update { $0.retentionDays = 30 }
        store.record([interval("old", ago: 20 * 24 * 60), interval("new", ago: 60)], now: now)
        #expect(store.log.intervals.count == 2)
        store.update(now: now) { $0.retentionDays = 14 }
        #expect(store.log.intervals.map(\.bundleID) == ["new"])
    }

    @Test func switchingTitlesOffRemovesStoredTitles() {
        let store = ActivityStore(storage: .inMemory())
        store.update { $0.recordWindowTitles = true }
        store.record([interval("a", ago: 60, title: "Secret")], now: now)
        #expect(store.log.intervals.first?.windowTitle == "Secret")
        store.update { $0.recordWindowTitles = false }
        #expect(store.log.intervals.first?.windowTitle == nil)
    }

    @Test func suggestionsComeFromTheStoredRules() {
        let store = ActivityStore(storage: .inMemory())
        store.saveRule(ActivityRule(bundleID: "a", appName: "A", labelType: .learningField, label: "LF 2"))
        store.record([interval("a", ago: 60, length: 40)], now: now)
        let segment = Segment(id: UUID(), kind: .work, startedAt: now.addingTimeInterval(-70 * 60), endedAt: now.addingTimeInterval(-10 * 60))
        let suggestions = store.suggestions(segments: [segment], from: now.addingTimeInterval(-86_400), to: now, now: now)
        #expect(suggestions.map(\.proposedNote) == ["Lernfeld: LF 2"])
        store.dismiss(suggestions[0].id)
        #expect(store.suggestions(segments: [segment], from: now.addingTimeInterval(-86_400), to: now, now: now).isEmpty)
    }

    @Test func oldSettingsFilesDecodeWithDefaults() throws {
        let decoded = try JSONDecoder().decode(ActivitySettings.self, from: Data("{\"enabled\":true}".utf8))
        #expect(decoded.enabled && decoded.onlyWhileTimerRuns && !decoded.recordWindowTitles && decoded.retentionDays == 14)
    }
}
