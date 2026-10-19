import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores

@MainActor
@Suite struct WorkModelCorrectionTests {
    static let id = "22222222-2222-4222-8222-222222222222"
    static let modelJSON = #"{"id":"\#(id)","createdAt":"2026-09-01T08:00:00Z","validFrom":"2026-09-01","validTo":null,"timezone":"Europe/Berlin","weeklyTargetSeconds":138600,"workdays":[1,2,3,4,5],"travelCountsAsWork":true,"roundingEnabled":true,"roundingMinutes":15,"schoolFullDayThresholdSeconds":10800,"schoolCreditSeconds":null,"dayBoundaryMinutes":0,"fixedBreaks":[{"start":"12:00","end":"12:30"}],"version":3}"#
    static let previewJSON = #"{"affectedFrom":"2026-09-01","affectedTo":null,"affectedDays":48,"balanceBeforeSeconds":3600,"balanceAfterSeconds":-1800,"differenceSeconds":-5400,"changedFields":["weeklyTargetSeconds","bogus"],"previousValidTo":null}"#

    private func model() throws -> WorkModel { try JSONCoding.makeDecoder().decode(WorkModel.self, from: Data(Self.modelJSON.utf8)) }

    private func store(_ transport: MockTransport) -> WorkModelStore {
        transport.enqueue("GET /api/v1/work-models", body: "[\(Self.modelJSON)]")
        return WorkModelStore(client: Fixtures.client(transport))
    }

    @Test func formRoundTripsTheModel() throws {
        let model = try model()
        var form = WorkModelForm(model: model)
        #expect(form.weeklyTarget == "38:30" && form.workdays == [1, 2, 3, 4, 5] && form.schoolThreshold == "3:00" && form.schoolCredit.isEmpty && form.validTo.isEmpty)
        guard case .success(let input) = form.build() else { Issue.record("valid"); return }
        #expect(input.weeklyTargetSeconds == 138600 && input.validTo == nil && input.schoolCreditSeconds == nil && input.fixedBreaks == [FixedBreak(start: "12:00", end: "12:30")])
        form.weeklyTarget = "35:00"
        form.validTo = "2027-08-31"
        guard case .success(let changed) = form.build() else { Issue.record("valid"); return }
        #expect(changed.weeklyTargetSeconds == 126000 && changed.validTo == "2027-08-31")
    }

    @Test func validationReportsTheBadFields() throws {
        var form = WorkModelForm(model: try model())
        form.weeklyTarget = "abc"; form.workdays = []; form.validFrom = "2026-02-30"; form.timezone = "Mars/Base"; form.roundingMinutes = "0"
        form.dayBoundaryMinutes = "720"; form.fixedBreaks = [FixedBreak(start: "13:00", end: "12:00")]; form.schoolCredit = "x"; form.validTo = "2020-01-01"
        guard case .failure(let errors) = form.build() else { Issue.record("invalid"); return }
        #expect(errors.fields == [.weekly, .workdays, .validFrom, .timezone, .roundingMinutes, .dayBoundary, .fixedBreaks, .schoolCredit])
        form.roundingEnabled = false
        form.roundingMinutes = "0"
        if case .failure(let off) = form.build() { #expect(!off.fields.contains(.roundingMinutes)) }
    }

    @Test func inputEncodesExplicitNullsAndKeepsDailyTargets() throws {
        var form = WorkModelForm(model: try model())
        form.dailyTargetSeconds = ["5": 14400]
        guard case .success(let input) = form.build() else { Issue.record("valid"); return }
        let json = try #require(try JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(input)) as? [String: Any])
        #expect(json["validTo"] is NSNull && json["schoolCreditSeconds"] is NSNull)
        #expect((json["dailyTargetSeconds"] as? [String: Int]) == ["5": 14400] && json["roundingMinutes"] as? Int == 15)
    }

    @Test func previewThenSaveSendsPutWithIfMatch() async throws {
        let transport = MockTransport()
        transport.enqueue("GET /api/v1/auth/session", body: Fixtures.sessionJSON(csrf: "tok"))
        transport.enqueue("POST /api/v1/work-models/\(Self.id)/preview", body: Self.previewJSON)
        transport.enqueue("PUT /api/v1/work-models/\(Self.id)", body: Self.modelJSON)
        let client = Fixtures.client(transport)
        try await client.refreshSession()
        transport.enqueue("GET /api/v1/work-models", body: "[\(Self.modelJSON)]")
        let store = WorkModelStore(client: client)
        await store.load()
        let model = try #require(store.models.first)
        #expect(store.supportsCorrection)
        var form = WorkModelForm(model: model)
        form.weeklyTarget = "35:00"
        #expect(!store.canSave(form: form))
        #expect(await store.save(model: model, form: form) == nil, "no save without preview")
        store.updatePreview(for: model, form: form, debounce: .milliseconds(1))
        #expect(store.preview == .loading)
        await store.waitForPreview()
        guard case .ready(let preview) = store.preview else { Issue.record("ready"); return }
        #expect(preview.differenceSeconds == -5400 && preview.affectedDays == 48 && preview.changedFieldNames == ["Wochen-Soll"])
        #expect(store.canSave(form: form))
        form.weeklyTarget = "34:00"
        #expect(!store.canSave(form: form), "a changed input needs a new preview")
        form.weeklyTarget = "35:00"
        #expect(await store.save(model: model, form: form) != nil)
        let put = transport.requests(matching: "PUT /api/v1/work-models/\(Self.id)")
        #expect(put.count == 1 && put[0].value(forHTTPHeaderField: "If-Match") == "3" && put[0].value(forHTTPHeaderField: "X-CSRF-Token") == "tok")
        #expect(store.preview == .idle)
    }

    @Test func invalidFormSkipsPreviewAndErrorsAreReported() async throws {
        let transport = MockTransport()
        transport.enqueue("POST /api/v1/work-models/\(Self.id)/preview", status: 409, body: #"{"error":{"code":"model_overlap","message":"x"}}"#)
        let store = store(transport)
        await store.load()
        let model = try #require(store.models.first)
        var form = WorkModelForm(model: model)
        form.workdays = []
        store.updatePreview(for: model, form: form, debounce: .milliseconds(1))
        #expect(store.preview == .invalid && transport.requests(matching: "POST /api/v1/work-models/\(Self.id)/preview").isEmpty)
        form.workdays = [1]
        store.updatePreview(for: model, form: form, debounce: .milliseconds(1))
        await store.waitForPreview()
        guard case .failed(let error) = store.preview else { Issue.record("failed"); return }
        #expect(error.knownCode == .modelOverlap && !store.canSave(form: form))
    }

    @Test func oldServersWithoutVersionCannotCorrect() throws {
        let old = try JSONCoding.makeDecoder().decode(WorkModel.self, from: Data(Self.modelJSON.replacingOccurrences(of: #","version":3"#, with: "").utf8))
        let current = try model()
        #expect(old.version == nil && ![old].supportsCorrection && [current].supportsCorrection)
    }
}
