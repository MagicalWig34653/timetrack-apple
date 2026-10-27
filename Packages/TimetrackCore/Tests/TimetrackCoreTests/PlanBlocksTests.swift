import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

// P13 (contract 0.35.0, ADR-0031): several plan blocks per day. Synthetic data only.

private let berlin = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
private let now = ISO8601DateFormatter().date(from: "2026-10-21T10:00:00Z")!

private enum BlockFixtures {
    static func systemInfo(_ apiVersion: String) -> String {
        #"{"backend":{"version":"0.35.0","apiVersion":"\#(apiVersion)"}}"#
    }

    static let splitDay = #"{"date":"2026-10-28","mode":"office","placeId":null,"note":null,"plannedStart":"08:00","plannedEnd":"17:00","plannedBreakMinutes":60,"plannedSeconds":28800,"blocks":[{"start":"08:00","end":"12:00","kind":"school","placeId":null,"note":"Mathe"},{"start":"13:00","end":"17:00","kind":"work","placeId":"55555555-5555-4555-8555-555555555555","note":null}],"planHints":["planned_break_part_short","planned_future_hint"]}"#

    static func planWeek(day: String = splitDay) -> String {
        #"""
        {"week":"2026-W44","from":"2026-10-26","to":"2026-11-01","days":[
         {"date":"2026-10-26","weekday":1,"targetSeconds":27720,"plannedSeconds":null,"blockedBy":null,"plan":null},
         {"date":"2026-10-27","weekday":2,"targetSeconds":0,"plannedSeconds":0,"blockedBy":"holiday","plan":{"date":"2026-10-27","mode":"home","note":"x","plannedStart":"09:00","plannedEnd":"10:00","plannedBreakMinutes":0,"plannedSeconds":3600,"blocks":[{"start":"09:00","end":"10:00","kind":"home"}],"planHints":[]}},
         {"date":"2026-10-28","weekday":3,"targetSeconds":27720,"plannedSeconds":28800,"blockedBy":null,"plan":\#(day)},
         {"date":"2026-10-29","weekday":4,"targetSeconds":27720,"plannedSeconds":null,"blockedBy":null,"plan":null},
         {"date":"2026-10-30","weekday":5,"targetSeconds":27720,"plannedSeconds":null,"blockedBy":null,"plan":null},
         {"date":"2026-10-31","weekday":6,"targetSeconds":0,"plannedSeconds":null,"blockedBy":null,"plan":null},
         {"date":"2026-11-01","weekday":7,"targetSeconds":0,"plannedSeconds":null,"blockedBy":null,"plan":null}],
         "totals":{"targetSeconds":110880,"plannedSeconds":28800,"differenceSeconds":-82080}}
        """#
    }

    static let timeWeekDay = #"{"date":"2026-10-26","weekday":1,"mark":"work","targetSeconds":27720,"plannedSeconds":28800,"planMode":"office","planBlocks":[{"start":"08:00","end":"12:00","kind":"school"},{"start":"13:00","end":"17:00","kind":"work"}],"planHints":["planned_break_short"],"planActualDifferenceSeconds":-1800,"workSeconds":27000,"creditSeconds":0,"rawWorkSeconds":27300,"breakSeconds":1800,"breakDeductionSeconds":0,"travelSeconds":0,"schoolSeconds":0,"balanceSeconds":0,"firstStart":null,"lastEnd":null,"segmentsCount":2,"absences":[],"provisional":false,"isToday":false,"isFuture":false}"#
}

private func block(_ start: String, _ end: String, _ kind: PlanBlockKind = .work) -> PlanTimeBlock { PlanTimeBlock(start: start, end: end, kind: kind) }

private func body(_ transport: MockTransport, _ key: String) -> [String: Any]? {
    transport.requests(matching: key).last?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
}

@Suite("P13 decoding")
struct PlanBlocksDecodingTests {
    @Test func planDayDecodesBlocksAndHintsAndDropsUnknownHints() throws {
        let week = try JSONCoding.makeDecoder().decode(PlanWeek.self, from: Data(BlockFixtures.planWeek().utf8))
        let plan = try #require(week.days[2].plan)
        #expect(plan.blocks.count == 2)
        #expect(plan.blocks[0] == PlanTimeBlock(start: "08:00", end: "12:00", kind: .school, placeId: nil, note: "Mathe"))
        #expect(plan.blocks[1].placeId == UUID(uuidString: "55555555-5555-4555-8555-555555555555"))
        #expect(plan.planHints == [.breakPartShort, .unknown].filter { $0 != .unknown })
        #expect(plan.plannedSeconds == 28800)
        #expect(plan.blocks.map(\.durationSeconds) == [14400, 14400])
    }

    @Test func oldServerWithoutBlocksDecodesAsEmpty() throws {
        let json = #"{"date":"2026-10-26","mode":"office","plannedStart":"08:00","plannedEnd":"16:30","plannedBreakMinutes":30,"plannedSeconds":28800}"#
        let plan = try JSONCoding.makeDecoder().decode(PlanDay.self, from: Data(json.utf8))
        #expect(plan.blocks.isEmpty && plan.planHints.isEmpty)
        #expect(plan.plannedStart == "08:00")
    }

    @Test func unknownBlockKindDecodesAsUnknown() throws {
        let block = try JSONCoding.makeDecoder().decode(PlanTimeBlock.self, from: Data(#"{"start":"08:00","end":"09:00","kind":"sabbatical"}"#.utf8))
        #expect(block.kind == .unknown)
    }

    @Test func timeWeekDayHasPlanBlocksHintsAndDifference() throws {
        let day = try JSONCoding.makeDecoder().decode(TimeWeekDay.self, from: Data(BlockFixtures.timeWeekDay.utf8))
        #expect(day.planBlocks?.count == 2)
        #expect(day.planHints == [.breakShort])
        #expect(day.planActualDifferenceSeconds == -1800)
        let old = BlockFixtures.timeWeekDay.replacingOccurrences(of: #""planBlocks":[{"start":"08:00","end":"12:00","kind":"school"},{"start":"13:00","end":"17:00","kind":"work"}],"planHints":["planned_break_short"],"planActualDifferenceSeconds":-1800,"#, with: "")
        let decodedOld = try JSONCoding.makeDecoder().decode(TimeWeekDay.self, from: Data(old.utf8))
        #expect(decodedOld.planBlocks == nil && decodedOld.planHints == nil && decodedOld.planActualDifferenceSeconds == nil)
    }

    @Test func sharedViewBlocksCarryNoPlaceOrNote() throws {
        let json = #"{"plan":[{"date":"2026-10-28","mode":"office","plannedStart":"08:00","plannedEnd":"17:00","plannedBreakMinutes":60,"plannedSeconds":28800,"blocks":[{"start":"08:00","end":"12:00","kind":"school"},{"start":"13:00","end":"17:00","kind":"work"}]},{"date":"2026-10-29","mode":"home"}]}"#
        let view = try JSONCoding.makeDecoder().decode(SharedView.self, from: Data(json.utf8))
        #expect(view.plan?[0].blocks?.map(\.kind) == [.school, .work])
        #expect(view.plan?[1].blocks == nil)
        let encoded = String(decoding: try JSONEncoder().encode(view.plan![0].blocks!), as: UTF8.self)
        #expect(!encoded.contains("placeId") && !encoded.contains("note"))
    }

    @Test func versionGate() {
        #expect(PlanBlocks.isSupported(apiVersion: "0.35.0"))
        #expect(PlanBlocks.isSupported(apiVersion: "0.36.1"))
        #expect(PlanBlocks.isSupported(apiVersion: "1.0.0"))
        #expect(!PlanBlocks.isSupported(apiVersion: "0.34.9"))
        #expect(!PlanBlocks.isSupported(apiVersion: "0.9.0"))
        #expect(!PlanBlocks.isSupported(apiVersion: nil))
        #expect(!PlanBlocks.isSupported(apiVersion: "dev"))
    }
}

@Suite("P13 drafts and editing")
struct PlanBlocksDraftTests {
    @Test func inputEncodesBlocksWithoutOldFieldsAndOldInputWithoutBlocks() throws {
        let withBlocks = PlanDayInput(mode: .office, blocks: [block("08:00", "12:00", .school)])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(withBlocks)) as? [String: Any])
        #expect(json["plannedStart"] == nil && json["plannedEnd"] == nil && json["plannedBreakMinutes"] == nil)
        #expect((json["blocks"] as? [[String: Any]])?.first?["kind"] as? String == "school")
        let old = PlanDayInput(mode: .office, plannedStart: "08:00", plannedEnd: "16:00", plannedBreakMinutes: 30)
        let oldJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        #expect(oldJSON["blocks"] == nil && oldJSON["plannedStart"] as? String == "08:00")
    }

    @Test func keepingSendsStoredBlocksAndEmptyListForOff() throws {
        let plan = try JSONCoding.makeDecoder().decode(PlanWeek.self, from: Data(BlockFixtures.planWeek().utf8)).days[2].plan!
        #expect(PlanDayInput(keeping: plan).blocks?.count == 2)
        #expect(PlanDayInput(keeping: plan).plannedStart == nil)
        #expect(PlanDayInput(keeping: plan, mode: .off).blocks == [])
        #expect(PlanDayInput(keeping: PlanDay(date: "2026-10-28", mode: .office, plannedStart: "08:00", plannedEnd: "16:00", plannedBreakMinutes: 0)).blocks == nil)
    }

    @Test func problemsAreNamed() {
        func problem(_ blocks: [PlanTimeBlock]) -> DraftProblem? { WeekPlan.problem(DayDraft(date: "2026-10-28", mode: .office, blocks: blocks)) }
        #expect(problem([block("08:00", "12:00"), block("12:00", "16:00")]) == nil) // touching is fine
        #expect(problem([block("08:00", "12:00"), block("11:00", "16:00")]) == .blocksOverlap)
        #expect(problem([block("13:00", "16:00"), block("08:00", "12:00")]) == .blocksOverlap)
        #expect(problem([block("10:00", "10:00")]) == .endBeforeStart)
        #expect(problem([block("8:00", "12:00")]) == .timesRequired)
        #expect(problem(Array(repeating: block("08:00", "08:05"), count: 33)) == .tooManyBlocks)
        var noted = block("08:00", "09:00")
        noted.note = String(repeating: "x", count: 201)
        #expect(problem([noted]) == .noteTooLong)
        #expect(WeekPlan.problem(DayDraft(date: "2026-10-28", mode: .off, blocks: [block("11:00", "10:00")])) == nil)
    }

    @Test func requestSendsTheFullOrderedListAndEmptyListsForOffAndUntimed() throws {
        let drafts = [
            DayDraft(date: "2026-10-26", mode: .office, note: " Plan ", blocks: [block("13:00", "17:00"), block("08:00", "12:00", .school)]),
            DayDraft(date: "2026-10-27", mode: .off, blocks: [block("08:00", "09:00")]),
            DayDraft(date: "2026-10-28", mode: .home),
            DayDraft(date: "2026-10-29")
        ]
        let request = WeekPlan.request(drafts, multi: true)
        #expect(request.days.count == 3 && request.replace)
        #expect(request.days[0].input.blocks?.map(\.start) == ["08:00", "13:00"])
        #expect(request.days[0].input.note == "Plan")
        #expect(request.days[1].input.blocks == [])
        #expect(request.days[2].input.blocks == [])
        let legacy = WeekPlan.request([DayDraft(date: "2026-10-26", mode: .office, start: "08:00", end: "16:00", breakMinutes: 30)], multi: false)
        #expect(legacy.days[0].input.blocks == nil && legacy.days[0].input.plannedStart == "08:00")
    }

    @Test func plannedSecondsIsTheSumOfBlocks() {
        let draft = DayDraft(date: "2026-10-28", mode: .office, blocks: [block("08:00", "12:00"), block("13:00", "17:00")])
        #expect(WeekPlan.plannedSeconds(draft) == 28800)
        #expect(WeekPlan.plannedSeconds(DayDraft(date: "2026-10-28", mode: .off, blocks: draft.blocks)) == nil)
    }

    @Test func hintsFollowTheServerRule() {
        #expect(WeekPlan.hints(for: [block("08:00", "17:00")]) == [.breakShort, .workStretchLong])
        #expect(WeekPlan.hints(for: [block("08:00", "12:00"), block("12:30", "16:30")]) == [])
        #expect(WeekPlan.hints(for: [block("08:00", "11:00"), block("11:10", "14:00")]) == [.breakPartShort])
        // school time is no working time, but also no break
        #expect(WeekPlan.hints(for: [block("08:00", "14:00", .school)]) == [])
        #expect(WeekPlan.hints(for: [block("08:00", "17:30"), block("17:30", "18:00")]).contains(.breakShort))
    }

    @Test func editingOperations() {
        let two = [block("08:00", "12:00", .school), block("13:00", "17:00")]
        let split = PlanBlockEditing.splitting(two, at: 0)
        #expect(split.map(\.start) == ["08:00", "10:00", "13:00"] && split[0].end == "10:00" && split[1].kind == .school)
        let tiny = [block("08:00", "08:05")]
        #expect(PlanBlockEditing.splitting(tiny, at: 0) == tiny && !PlanBlockEditing.canSplit(tiny, at: 0))
        let merged = PlanBlockEditing.mergingWithNext(two, at: 0)
        #expect(merged.count == 1 && merged[0].start == "08:00" && merged[0].end == "17:00" && merged[0].kind == .school)
        #expect(PlanBlockEditing.deleting(two, at: 1) == [two[0]])
        #expect(PlanBlockEditing.adding(to: [], kind: .work) == [block("08:00", "12:00")])
        #expect(PlanBlockEditing.adding(to: two, kind: .travel).last == block("17:00", "18:00", .travel))
        let late = [block("22:00", "23:59")]
        #expect(PlanBlockEditing.adding(to: late, kind: .work) == late)
        #expect(PlanBlockEditing.adding(to: Array(repeating: block("08:00", "08:05"), count: 32), kind: .work).count == 32)
        #expect(PlanBlockEditing.gapMinutes(two) == [60])
        #expect(PlanBlockEditing.sorted([block("13:00", "14:00"), block("08:00", "09:00")]).first?.start == "08:00")
    }

    @Test func modePrefillsBlocksWithBreakAsGap() {
        let suggestion = WindowSuggestion(start: "08:00", end: "16:30", breakMinutes: 30, source: .history)
        let draft = WeekPlan.withMode(DayDraft(date: "2026-10-28"), .home, suggestion: suggestion, targetSeconds: 27720, multi: true)
        #expect(draft.blocks.count == 2 && draft.blocks.allSatisfy { $0.kind == .home } && draft.start.isEmpty)
        #expect(draft.blocks[0].start == "08:00" && draft.blocks[1].end == "16:30")
        #expect(draft.blocks[1].startMinutes! - draft.blocks[0].endMinutes! == 30)
        let retagged = WeekPlan.withMode(draft, .customer, suggestion: suggestion, targetSeconds: 27720, multi: true)
        #expect(retagged.blocks.allSatisfy { $0.kind == .customer } && retagged.blocks.count == 2)
        let mixed = DayDraft(date: "2026-10-28", mode: .office, blocks: [block("08:00", "12:00", .school), block("13:00", "17:00", .office)])
        #expect(WeekPlan.withMode(mixed, .home, suggestion: suggestion, targetSeconds: 0, multi: true).blocks.map(\.kind) == [.school, .home])
        #expect(WeekPlan.withMode(mixed, .off, suggestion: suggestion, targetSeconds: 0, multi: true).blocks.isEmpty)
        let old = WeekPlan.withMode(DayDraft(date: "2026-10-28"), .home, suggestion: suggestion, targetSeconds: 27720, multi: false)
        #expect(old.blocks.isEmpty && old.start == "08:00" && old.breakMinutes == 30)
    }
}

@MainActor
@Suite("P13 store")
struct PlanBlocksStoreTests {
    private func store(_ transport: MockTransport, apiVersion: String?, injected: Bool? = nil) -> WeekPlanStore {
        if let apiVersion { transport.enqueue("GET /api/v1/system/info", body: BlockFixtures.systemInfo(apiVersion)) }
        else { transport.enqueue("GET /api/v1/system/info", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#) }
        for week in ["2026-W43", "2026-W42", "2026-W41", "2026-W40"] { transport.enqueue("GET /api/v1/time/weeks/\(week)", status: 500, body: "{}") }
        return WeekPlanStore(client: Fixtures.client(transport), calendar: berlin, now: now, supportsBlocks: injected)
    }

    @Test func loadsBlocksTracksDirtyAndSavesTheFullOrderedList() async {
        let transport = MockTransport()
        let store = store(transport, apiVersion: "0.35.0")
        transport.enqueue("GET /api/v1/plan/weeks/2026-W44", body: BlockFixtures.planWeek())
        await store.load()
        #expect(store.supportsBlocks && !store.isDirty)
        #expect(store.drafts[2].blocks.count == 2 && store.drafts[2].start.isEmpty)
        #expect(store.totals.plannedSeconds == 28800) // 08-12 + 13-17; blocked day counts 0
        store.splitBlock(2, at: 1)
        #expect(store.isDirty && store.drafts[2].blocks.count == 3)
        store.mergeBlock(2, at: 1)
        #expect(!store.isDirty)
        store.addBlock(2)
        store.updateBlock(2, at: 2) { $0.kind = .travel; $0.note = "Zug" }
        #expect(store.isDirty && store.drafts[2].blocks[2] == PlanTimeBlock(start: "17:00", end: "18:00", kind: .travel, note: "Zug"))
        transport.enqueue("PUT /api/v1/plan/weeks/2026-W44", body: BlockFixtures.planWeek())
        #expect(await store.save())
        let days = body(transport, "PUT /api/v1/plan/weeks/2026-W44")?["days"] as? [[String: Any]]
        let day = days?.first { $0["date"] as? String == "2026-10-28" }
        let blocks = day?["blocks"] as? [[String: Any]]
        #expect(blocks?.map { $0["start"] as? String } == ["08:00", "13:00", "17:00"])
        #expect(day?["plannedStart"] == nil)
        // the blocked day keeps its stored plan, with its blocks
        #expect((days?.first { $0["date"] as? String == "2026-10-27" }?["blocks"] as? [[String: Any]])?.count == 1)
        #expect(!store.isDirty)
    }

    @Test func overlapIsCaughtLocallyAndSendsNothing() async {
        let transport = MockTransport()
        let store = store(transport, apiVersion: "0.35.0")
        transport.enqueue("GET /api/v1/plan/weeks/2026-W44", body: BlockFixtures.planWeek())
        await store.load()
        store.updateBlock(2, at: 1) { $0.start = "11:00" }
        #expect(store.problem(at: 2) == .blocksOverlap)
        #expect(await store.save() == false && store.showProblems)
        #expect(transport.requests(matching: "PUT /api/v1/plan/weeks/2026-W44").isEmpty)
    }

    @Test func oldServerKeepsTheSingleWindowPlanner() async {
        let transport = MockTransport()
        let store = store(transport, apiVersion: "0.34.0")
        let old = BlockFixtures.planWeek(day: #"{"date":"2026-10-28","mode":"office","plannedStart":"08:00","plannedEnd":"16:30","plannedBreakMinutes":30,"plannedSeconds":28800}"#)
        transport.enqueue("GET /api/v1/plan/weeks/2026-W44", body: old)
        await store.load()
        #expect(!store.supportsBlocks)
        #expect(store.drafts[2].blocks.isEmpty && store.drafts[2].start == "08:00" && store.drafts[2].breakMinutes == 30)
        store.addBlock(2)
        #expect(!store.isDirty)
        store.update(2, DayDraft(date: "2026-10-28", mode: .office, start: "09:00", end: "17:00", breakMinutes: 45))
        transport.enqueue("PUT /api/v1/plan/weeks/2026-W44", body: old)
        #expect(await store.save())
        let day = (body(transport, "PUT /api/v1/plan/weeks/2026-W44")?["days"] as? [[String: Any]])?.first { $0["date"] as? String == "2026-10-28" }
        #expect(day?["blocks"] == nil && day?["plannedStart"] as? String == "09:00" && day?["plannedBreakMinutes"] as? Int == 45)
    }

    @Test func missingSystemInfoFallsBackToTheOldPlanner() async {
        let transport = MockTransport()
        let store = store(transport, apiVersion: nil)
        transport.enqueue("GET /api/v1/plan/weeks/2026-W44", body: BlockFixtures.planWeek())
        await store.load()
        #expect(!store.supportsBlocks)
        #expect(store.drafts[2].start == "08:00" && store.drafts[2].blocks.isEmpty)
    }

    @Test func serverErrorsMapToGermanTextsInContext() async {
        let codes = ["plan_time_invalid", "plan_blocks_overlap", "plan_blocks_invalid", "plan_kind_invalid", "plan_note_invalid"]
        for code in codes {
            let transport = MockTransport()
            let store = store(transport, apiVersion: "0.35.0", injected: true)
            transport.enqueue("GET /api/v1/plan/weeks/2026-W44", body: BlockFixtures.planWeek())
            await store.load()
            store.updateBlock(2, at: 0) { $0.end = "11:00" }
            transport.enqueue("PUT /api/v1/plan/weeks/2026-W44", status: 400, body: #"{"error":{"code":"\#(code)","message":"x"}}"#)
            #expect(await store.save() == false)
            let error = store.error
            #expect(error?.knownCode != nil)
            let text = error?.germanMessage(in: .planBlocks) ?? ""
            #expect(text.contains("Planblock") || text.contains("Planblöcke"))
            #expect(!text.contains("error.") && error?.germanDescription.contains("error.") == false)
            #expect(store.isDirty) // nothing lost after a rejected save
        }
    }
}

@MainActor
@Suite("P13 calendar sync")
struct PlanBlocksCalendarTests {
    private func day(_ date: LocalDay, _ blocks: [PlanTimeBlock], mode: PlanMode = .office) -> PlanDay { PlanDay(date: date, mode: mode, note: "geheim", blocks: blocks) }

    @Test func eachBlockBecomesATimedEntryWithPerBlockKeys() {
        let plan: [LocalDay: PlanDay] = [
            "2026-10-28": day("2026-10-28", [block("13:00", "17:00"), block("08:00", "12:00", .school)]),
            "2026-10-29": day("2026-10-29", [], mode: .home)
        ]
        let entries = CalendarWritePlanner.desiredPlanDays(from: plan, from: "2026-10-26", to: "2026-11-01") { "Arbeit: \($0.rawValue)" }
        #expect(entries.map(\.key) == ["plan/2026-10-28/1", "plan/2026-10-28/2", "plan/2026-10-29"])
        #expect(entries[0].title == "Schule" && entries[0].startMinute == 480 && entries[0].endMinute == 720)
        #expect(entries[1].title == "Arbeit" && entries[1].startMinute == 780)
        #expect(!entries[2].isTimed && entries[2].title == "Arbeit: home")
        #expect(!entries.contains { $0.title.contains("geheim") })
    }

    @Test func markerKeysRoundTrip() {
        #expect(EntryMarker.key(from: EntryMarker.url(forKey: "plan/2026-10-28/2"), notes: nil) == "plan/2026-10-28/2")
        #expect(EntryMarker.key(from: EntryMarker.url(forKey: "plan/2026-10-28"), notes: nil) == "plan/2026-10-28")
        #expect(EntryMarker.key(from: nil, notes: EntryMarker.notes(forKey: "plan/2026-10-28/3")) == "plan/2026-10-28/3")
        #expect(EntryMarker.key(from: URL(string: "timetrack://plan/2026-10-28/0"), notes: nil) == nil)
        #expect(EntryMarker.key(from: URL(string: "timetrack://plan/2026-10-28/x"), notes: nil) == nil)
        #expect(EntryMarker.key(from: URL(string: "timetrack://plan/2026-10-28/1/2"), notes: nil) == nil)
    }

    @Test func reconciliationCreatesUpdatesMovesAndDeletesPerBlock() {
        func entry(_ n: Int, _ s: Int, _ e: Int, _ title: String = "Arbeit") -> CalendarEntry {
            CalendarEntry(key: EntryMarker.planBlockKey("2026-10-28", number: n), firstDay: "2026-10-28", lastDay: "2026-10-28", title: title, startMinute: s, endMinute: e)
        }
        func written(_ id: String, _ e: CalendarEntry) -> WrittenEvent {
            WrittenEvent(eventID: id, key: e.key, firstDay: e.firstDay, lastDay: e.lastDay, title: e.title, startMinute: e.startMinute, endMinute: e.endMinute)
        }
        let first = entry(1, 480, 720), second = entry(2, 780, 1020)
        let created = CalendarReconciler.plan(desired: [first, second], existing: [], records: [:], from: "2026-10-26", to: "2026-11-01")
        #expect(created.operations.count == 2)
        let existing = [written("a", first), written("b", second)]
        let same = CalendarReconciler.plan(desired: [first, second], existing: existing, records: [:], from: "2026-10-26", to: "2026-11-01")
        #expect(same.operations.isEmpty && same.adopt.count == 2)
        // a time change is an update, not a recreate
        let moved = CalendarReconciler.plan(desired: [first, entry(2, 840, 1020)], existing: existing, records: [:], from: "2026-10-26", to: "2026-11-01")
        #expect(moved.operations == [.update(eventID: "b", entry(2, 840, 1020))])
        // merging two blocks into one deletes the surplus event
        let merged = CalendarReconciler.plan(desired: [entry(1, 480, 1020)], existing: existing, records: [:], from: "2026-10-26", to: "2026-11-01")
        #expect(merged.operations.contains(.delete(eventID: "b")) && merged.operations.contains(.update(eventID: "a", entry(1, 480, 1020))))
        // the all-day event of the day before blocks existed is replaced by block events
        let allDay = CalendarEntry(key: "plan/2026-10-28", firstDay: "2026-10-28", lastDay: "2026-10-28", title: "Arbeit: Büro")
        let migrated = CalendarReconciler.plan(desired: [first], existing: [written("old", allDay)], records: [:], from: "2026-10-26", to: "2026-11-01")
        #expect(migrated.operations.contains(.delete(eventID: "old")) && migrated.operations.contains(.create(first)))
        // an event the user deleted by hand stays gone while the block is unchanged, but returns when its time changes
        let record = CalendarLedgerRecord(eventID: "a", entry: first)
        let removed = CalendarReconciler.plan(desired: [first], existing: [], records: [first.key: record], from: "2026-10-26", to: "2026-11-01")
        #expect(removed.operations.isEmpty && removed.userRemoved == [first.key])
        let changed = CalendarReconciler.plan(desired: [entry(1, 500, 720)], existing: [], records: [first.key: record], from: "2026-10-26", to: "2026-11-01")
        #expect(changed.operations.count == 1)
    }

    @Test func storeWritesTimedEventsAndFollowsBlockChanges() async {
        let provider = InMemoryDeviceCalendarProvider(access: .full, calendars: [DeviceCalendarInfo(id: "work", title: "Arbeit", accountTitle: "iCloud")])
        let store = DeviceCalendarStore(provider: provider, storage: MemoryCalendarPreferencesStorage(), ledgerStorage: MemoryCalendarLedgerStorage())
        await store.setMode(.readWrite, for: "work")
        store.setWritePlanDays(true)
        let source = PlanSource()
        source.plan = [PlanDay(date: "2026-10-28", mode: .office, blocks: [block("08:00", "12:00", .school), block("13:00", "17:00")]), PlanDay(date: "2026-10-29", mode: .home)]
        await store.syncAll(source: source, calendar: berlin, now: now) { "Arbeit: \($0.rawValue)" }
        #expect(provider.written.values.map(\.entry.key).sorted() == ["plan/2026-10-28/1", "plan/2026-10-28/2", "plan/2026-10-29"])
        let events = provider.events(from: berlin.interval(of: "2026-10-28")!.start, to: berlin.interval(of: "2026-10-29")!.start, calendarIDs: ["work"])
        #expect(events.filter { !$0.isAllDay }.count == 2)
        source.plan = [PlanDay(date: "2026-10-28", mode: .office, blocks: [block("08:00", "17:00")]), PlanDay(date: "2026-10-29", mode: .home)]
        await store.syncAll(source: source, calendar: berlin, now: now) { "Arbeit: \($0.rawValue)" }
        #expect(provider.written.values.map(\.entry.key).sorted() == ["plan/2026-10-28/1", "plan/2026-10-29"])
        #expect(provider.written.values.first { $0.entry.key == "plan/2026-10-28/1" }?.entry.endMinute == 1020)
        // a second identical sync changes nothing
        let before = provider.written
        await store.syncAll(source: source, calendar: berlin, now: now) { "Arbeit: \($0.rawValue)" }
        #expect(provider.written == before)
    }
}

private final class PlanSource: CalendarSyncSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _plan: [PlanDay] = []
    var plan: [PlanDay] { get { lock.withLock { _plan } } set { lock.withLock { _plan = newValue } } }
    func calendarAbsences(from: LocalDay, to: LocalDay) async throws -> [Absence] { [] }
    func calendarPlanDays(from: LocalDay, to: LocalDay) async throws -> [PlanDay] { plan.filter { $0.date >= from && $0.date <= to } }
}
