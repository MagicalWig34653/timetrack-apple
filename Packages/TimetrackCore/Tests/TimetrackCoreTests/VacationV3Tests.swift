import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

private func absence(_ id: Int, _ kind: AbsenceKind = .vacation, _ start: LocalDay, _ end: LocalDay? = nil, _ status: AbsenceStatus = .planned, attachments: Int = 0) -> Absence {
    Absence(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", id))!, kind: kind, startDate: start, endDate: end ?? start,
            status: status, countedHalfDays: 2, attachmentCount: attachments)
}

@Suite struct VacationRingSegmentsTests {
    private func balance(booked: Int, planned: Int, available: Int, afterPlanned: Int, entitlement: Int = 60) -> VacationBalance {
        VacationBalance(year: 2026, entitlementHalfDays: entitlement, bookedHalfDays: booked, plannedHalfDays: planned, availableHalfDays: available, availableAfterPlannedHalfDays: afterPlanned)
    }

    @Test func splitsBookedPlannedAndFree() {
        let ring = VacationRingSegments(balance(booked: 20, planned: 10, available: 40, afterPlanned: 30))
        #expect(ring.capacityHalfDays == 60)
        #expect(abs(ring.bookedFraction - 1.0 / 3) < 1e-9)
        #expect(abs(ring.plannedFraction - 1.0 / 6) < 1e-9)
        #expect(abs(ring.freeFraction - 0.5) < 1e-9)
        #expect(!ring.isOverPlanned)
    }

    @Test func overPlanningFillsTheRingAndIsFlagged() {
        let ring = VacationRingSegments(balance(booked: 20, planned: 50, available: 40, afterPlanned: -10))
        #expect(ring.isOverPlanned)
        #expect(abs(ring.bookedFraction + ring.plannedFraction - 1) < 1e-9)
        #expect(ring.freeFraction == 0)
    }

    @Test func snapshotBalanceWithoutEntitlementStillHasCapacity() {
        // After a snapshot the year's entitlement is 0, the capacity comes from booked + available.
        let ring = VacationRingSegments(balance(booked: 4, planned: 2, available: 26, afterPlanned: 24, entitlement: 0))
        #expect(ring.capacityHalfDays == 30)
        #expect(ring.freeFraction > 0.7)
    }

    @Test func emptyOrNegativeBalanceIsAllZero() {
        let ring = VacationRingSegments(balance(booked: 0, planned: 0, available: 0, afterPlanned: 0, entitlement: 0))
        #expect(ring.bookedFraction == 0 && ring.plannedFraction == 0 && ring.freeFraction == 1)
        let negative = VacationRingSegments(balance(booked: 70, planned: 0, available: -10, afterPlanned: -10))
        #expect(negative.capacityHalfDays == 70)
        #expect(negative.bookedFraction == 1)
    }
}

@Suite struct AbsenceListOptionsTests {
    let today: LocalDay = "2026-10-19"
    let list = [
        absence(1, .vacation, "2026-12-21", "2026-12-23", .planned),
        absence(2, .sick, "2026-03-02", "2026-03-03", .taken, attachments: 1),
        absence(3, .vacation, "2026-05-04", "2026-05-06", .taken, attachments: 2),
        absence(4, .excused, "2026-11-02", nil, .requested),
        absence(5, .vacation, "2026-10-19", "2026-10-20", .approved),
    ]

    @Test func defaultKeepsEverythingByDate() {
        let result = AbsenceListOptions().apply(to: list, today: today)
        #expect(result.map(\.startDate) == ["2026-03-02", "2026-05-04", "2026-10-19", "2026-11-02", "2026-12-21"])
        #expect(AbsenceListOptions().isDefault && AbsenceListOptions().isDefaultSort)
    }

    @Test func filtersByKindStatusAndAttachment() {
        var options = AbsenceListOptions()
        options.kinds = [.vacation]
        #expect(options.apply(to: list, today: today).count == 3)
        options.statuses = [.taken, .approved]
        #expect(options.apply(to: list, today: today).map(\.startDate) == ["2026-05-04", "2026-10-19"])
        options.attachment = .with
        #expect(options.apply(to: list, today: today).map(\.startDate) == ["2026-05-04"])
        options.attachment = .without
        #expect(options.apply(to: list, today: today).map(\.startDate) == ["2026-10-19"])
        #expect(options.activeFilterCount == 4 - 1) // kinds, statuses, attachment (period is off)
    }

    @Test func unknownKindCountsAsOther() {
        var options = AbsenceListOptions()
        options.kinds = [.other]
        let odd = absence(9, .unknown, "2026-01-05")
        #expect(options.apply(to: [odd] + list, today: today).map(\.kind) == [.unknown])
    }

    @Test func periodUpcomingPastAndCustomUseOverlap() {
        var options = AbsenceListOptions()
        options.period = .upcoming
        #expect(options.apply(to: list, today: today).map(\.startDate) == ["2026-10-19", "2026-11-02", "2026-12-21"]) // ends today counts as upcoming
        options.period = .past
        #expect(options.apply(to: list, today: today).map(\.startDate) == ["2026-03-02", "2026-05-04"])
        options.period = .custom(from: "2026-05-06", to: "2026-10-19")
        #expect(options.apply(to: list, today: today).map(\.startDate) == ["2026-05-04", "2026-10-19"]) // overlap at both edges
        options.period = .custom(from: nil, to: "2026-03-01")
        #expect(options.apply(to: list, today: today).isEmpty)
        options.period = .custom(from: "2026-12-23", to: nil)
        #expect(options.apply(to: list, today: today).map(\.startDate) == ["2026-12-21"])
    }

    @Test func sortsByKindAndStatusInWorkflowOrderWithStableTies() {
        var options = AbsenceListOptions()
        options.sort = .kind
        #expect(options.apply(to: list, today: today).map(\.kind) == [.vacation, .vacation, .vacation, .sick, .excused])
        #expect(options.apply(to: list, today: today).prefix(3).map(\.startDate) == ["2026-05-04", "2026-10-19", "2026-12-21"])
        options.sort = .status
        #expect(options.apply(to: list, today: today).map(\.status) == [.planned, .requested, .approved, .taken, .taken])
        options.ascending = false
        #expect(options.apply(to: list, today: today).map(\.status) == [.taken, .taken, .approved, .requested, .planned])
        options.sort = .date
        #expect(options.apply(to: list, today: today).first?.startDate == "2026-12-21")
        #expect(!options.isDefaultSort)
    }

    @Test func resetKeepsSortOnly() {
        var options = AbsenceListOptions()
        options.kinds = [.sick]; options.attachment = .with; options.period = .past; options.sort = .status; options.ascending = false
        let reset = options.resettingFilters()
        #expect(!reset.hasFilters && reset.sort == .status && !reset.ascending)
    }

    @Test func codableRoundTripIncludingCustomPeriod() throws {
        var options = AbsenceListOptions()
        options.kinds = [.vacation, .sick]; options.statuses = [.planned]; options.attachment = .without; options.sort = .kind; options.ascending = false
        options.period = .custom(from: "2026-01-01", to: nil)
        let decoded = try JSONDecoder().decode(AbsenceListOptions.self, from: JSONEncoder().encode(options))
        #expect(decoded == options)
    }

    @Test func persistenceRoundTripAndDefaultRemovesKey() {
        let suite = "vacation-v3-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AbsenceListOptions.load(from: defaults).isDefault)
        var options = AbsenceListOptions()
        options.attachment = .with
        options.save(to: defaults)
        #expect(AbsenceListOptions.load(from: defaults) == options)
        AbsenceListOptions().save(to: defaults)
        #expect(defaults.data(forKey: AbsenceListOptions.storageKey) == nil)
        defaults.set(Data("garbage".utf8), forKey: AbsenceListOptions.storageKey)
        #expect(AbsenceListOptions.load(from: defaults).isDefault)
    }
}

@MainActor
@Suite struct AbsenceAttachmentTests {
    let calendar = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
    let now = Date(timeIntervalSince1970: 1_792_130_820)
    static let fileJSON = #"{"id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","name":"Krankschein.pdf","size":8,"sha256":"abc","contentType":"application/pdf","backend":"db","createdAt":"2026-03-03T08:00:00Z"}"#

    @Test func decodesAttachmentCountAndDefaultsToZero() throws {
        let json = #"[{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","version":1,"kind":"sick","startDate":"2026-03-02","endDate":"2026-03-03","status":"taken","countedHalfDays":0,"attachmentCount":2},{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","version":1,"kind":"vacation","startDate":"2026-04-02","endDate":"2026-04-03","status":"planned","countedHalfDays":4}]"#
        let decoded = try JSONCoding.makeDecoder().decode([Absence].self, from: Data(json.utf8))
        #expect(decoded.map(\.attachmentCount) == [2, 0])
    }

    @Test func listSendsHasAttachmentOnlyWhenAsked() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/absences", body: "[]")
        let client = Fixtures.client(transport)
        _ = try await client.listAbsences(from: "2026-01-01", to: "2026-12-31")
        #expect(transport.requests(matching: "GET /api/v1/absences").last?.url?.query == "from=2026-01-01&to=2026-12-31")
        _ = try await client.listAbsences(from: "2026-01-01", to: "2026-12-31", hasAttachment: true)
        #expect(transport.requests(matching: "GET /api/v1/absences").last?.url?.query == "from=2026-01-01&to=2026-12-31&hasAttachment=true")
        _ = try await client.listAbsences(from: "2026-01-01", to: "2026-12-31", hasAttachment: false)
        #expect(transport.requests(matching: "GET /api/v1/absences").last?.url?.query?.hasSuffix("hasAttachment=false") == true)
    }

    @Test func storeListsAttachmentsAndFetchesInlineForPreviewableTypes() async throws {
        let transport = MockTransport()
        let id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        transport.enqueue("GET /api/v1/absences/\(id)/attachments", body: "[\(Self.fileJSON)]")
        transport.enqueue("GET /api/v1/files/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", body: "%PDF-1.4")
        let store = PlanningStore(client: Fixtures.client(transport), calendar: calendar, now: now, defaults: UserDefaults(suiteName: "v3-\(UUID().uuidString)")!)
        let item = Absence(id: UUID(uuidString: id)!, kind: .sick, startDate: "2026-03-02", endDate: "2026-03-03", status: .taken, countedHalfDays: 0, attachmentCount: 1)
        let files = try await store.attachments(of: item)
        #expect(files.count == 1 && files[0].supportsInline)
        let data = try await store.fileData(files[0])
        #expect(String(decoding: data, as: UTF8.self) == "%PDF-1.4")
        #expect(transport.requests(matching: "GET /api/v1/files/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee").last?.url?.query == "disposition=inline")
    }

    @Test func nonPreviewableTypeIsFetchedWithoutInline() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/files/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", body: "x")
        let file = FileMeta(id: UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!, name: "scan.heic", size: 1, contentType: "image/heic")
        #expect(!file.supportsInline)
        _ = try await Fixtures.client(transport).downloadFile(id: file.id, inline: file.supportsInline)
        #expect(transport.requests(matching: "GET /api/v1/files/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee").last?.url?.query == nil)
    }

    @Test func contentTypeParametersAndCaseAreIgnoredForInline() {
        #expect(FileMeta(id: UUID(), name: "a", size: 1, contentType: "Text/Plain; charset=utf-8").supportsInline)
        #expect(!FileMeta(id: UUID(), name: "a", size: 1, contentType: "image/svg+xml").supportsInline)
    }

    @Test func safeFileNameStripsPathPartsAndKeepsExtension() {
        #expect(FileMeta(id: UUID(), name: "../../etc/passwd.pdf", size: 1, contentType: "x").safeFileName == "_.._etc_passwd.pdf")
        #expect(FileMeta(id: UUID(), name: "  ", size: 1, contentType: "x").safeFileName == "attachment")
        #expect(FileMeta(id: UUID(), name: "Krankschein.pdf", size: 1, contentType: "x").safeFileName == "Krankschein.pdf")
    }

    @Test func storeRemembersListOptions() {
        let suite = "v3-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlanningStore(client: Fixtures.client(MockTransport()), calendar: calendar, now: now, defaults: defaults)
        #expect(store.listOptions.isDefault)
        store.listOptions.statuses = [.planned]
        let again = PlanningStore(client: Fixtures.client(MockTransport()), calendar: calendar, now: now, defaults: defaults)
        #expect(again.listOptions.statuses == [.planned])
    }
}
