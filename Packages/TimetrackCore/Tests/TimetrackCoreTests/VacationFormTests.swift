import Foundation
import Testing
@testable import TimetrackCore
@testable import TimetrackStores
#if canImport(PDFKit)
import PDFKit
import CoreGraphics
#endif

// AB1: vacation request form. Port of the PWA's vacation-form library; every PDF here is generated in the tests (synthetic).

private func model(_ validFrom: String = "2026-01-01", validTo: String? = nil, workdays: [Int] = [1, 2, 3, 4, 5], daily: [String: Int]? = nil) -> WorkModel {
    let dailyJSON = daily.map { ",\"dailyTargetSeconds\":{" + $0.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",") + "}" } ?? ""
    let to = validTo.map { "\"\($0)\"" } ?? "null"
    let json = #"{"id":"44444444-4444-4444-8444-444444444444","validFrom":"\#(validFrom)","validTo":\#(to),"weeklyTargetSeconds":144000,"workdays":\#(workdays)\#(dailyJSON)}"#
    return try! JSONCoding.makeDecoder().decode(WorkModel.self, from: Data(json.utf8))
}

private func holiday(_ day: String, kind: CalendarDayKind = .holiday) -> CalendarDay {
    CalendarDay(startDate: day, endDate: day, name: "Feiertag", kind: kind, source: .builtin)
}

struct FormFormatTests {
    @Test func datesFollowThePWAFormats() {
        #expect(FormDateFormat.dotted.format("2026-07-06") == "06.07.2026")
        #expect(FormDateFormat.shortDotted.format("2026-07-06") == "6.7.26")
        #expect(FormDateFormat.iso.format("2026-07-06") == "2026-07-06")
        #expect(FormDateFormat.dotted.format("6.7.2026") == "6.7.2026") // unparsable input is returned unchanged
        #expect(FormDateFormat.dotted.format("2026-7-06") == "2026-7-06")
    }

    @Test func daysAreGermanDecimalsInHalfSteps() {
        #expect(FormDays.format(30) == "30")
        #expect(FormDays.format(4.5) == "4,5")
        #expect(FormDays.format(0) == "0")
        #expect(FormDays.format(4.26) == "4,5") // rounded to half days
        #expect(FormDays.format(-0.5) == "-0,5")
    }

    @Test func fileNameMatchesThePWA() {
        #expect(vacationRequestFileName(from: "2026-07-06", to: "2026-07-17") == "Urlaubsantrag_2026-07-06_2026-07-17.pdf")
    }
}

struct FormMappingParsingTests {
    @Test func readsAMappingTheWebAppWrote() throws {
        let json = #"""
        {"version":1,"person":{"lastName":"Muster","firstName":"Max","personnelNo":"4711","department":"IT","place":"Köln"},
         "dateFormat":"d.M.yy","flatten":true,
         "fields":{"Von":{"source":"dateFrom"},"Frei":{"source":"freeRange","index":2,"dateFormat":"iso"},
                   "Haken":{"source":"fixedCheckbox","checked":true},"Text":{"source":"fixedText","text":"Hallo"}},
         "overlays":[{"id":"o1","page":1,"x":120.5,"y":300,"fontSize":12,"binding":{"source":"today"}}]}
        """#
        let mapping = FormMapping(json: try JSONCoding.makeDecoder().decode(JSONValue.self, from: Data(json.utf8)))
        #expect(mapping.person == FormPerson(lastName: "Muster", firstName: "Max", personnelNo: "4711", department: "IT", place: "Köln"))
        #expect(mapping.dateFormat == .shortDotted && mapping.flatten)
        #expect(mapping.fields["Frei"] == FormBinding(source: .freeRange, index: 2, dateFormat: .iso))
        #expect(mapping.fields["Haken"]?.checked == true && mapping.fields["Text"]?.text == "Hallo")
        #expect(mapping.overlays == [FormOverlay(id: "o1", page: 1, x: 120.5, y: 300, fontSize: 12, binding: FormBinding(source: .today))])
        #expect(mapping.freeRangeSlots == 2)
    }

    @Test func dropsUnknownSourcesAndClampsNumbers() throws {
        let json = #"""
        {"dateFormat":"nonsense","fields":{"A":{"source":"futureSource"},"B":{"source":"freeRangeFrom","index":99},"C":{"source":"freeRangeTo","index":-3},
           "D":"not an object","E":{"source":"fixedText"}},
         "overlays":[{"id":"x","page":-2,"x":"bad","y":5,"fontSize":500,"binding":{"source":"today"}},{"id":"y","binding":{"source":"nope"}},{"page":0,"binding":{"source":"today"}}]}
        """#
        let mapping = FormMapping(json: try JSONCoding.makeDecoder().decode(JSONValue.self, from: Data(json.utf8)))
        #expect(mapping.dateFormat == .dotted) // unknown format falls back
        #expect(mapping.fields.keys.sorted() == ["B", "C", "E"])
        #expect(mapping.fields["B"]?.index == maxFreeRanges && mapping.fields["C"]?.index == 1)
        #expect(mapping.fields["E"]?.text == "") // fixed text without text becomes empty
        #expect(mapping.overlays.count == 1)
        #expect(mapping.overlays[0].page == 0 && mapping.overlays[0].x == 0 && mapping.overlays[0].fontSize == 48)
    }

    @Test func nonObjectsGiveTheEmptyMapping() {
        #expect(FormMapping(json: nil) == FormMapping())
        #expect(FormMapping(json: .array([])) == FormMapping())
        #expect(FormMapping(json: .null) == FormMapping())
    }

    @Test func everySourceIdOfThePWAIsKnown() {
        // Raw values are stored in the mapping, so they must equal the PWA's ids.
        let pwa = ["lastName", "firstName", "fullName", "personnelNo", "department", "place", "entitlementTotal", "entitlementYear", "carryOver",
                   "additional", "paidOut", "restBefore", "restAfter", "dateFrom", "dateTo", "dateRange", "workingDays", "freeRangeFrom",
                   "freeRangeTo", "freeRange", "freeDaysCount", "hasFreeDays", "substitute", "today", "fixedText", "fixedCheckbox"]
        #expect(Set(FormSource.allCases.map(\.rawValue)) == Set(pwa))
    }
}

struct FormCalendarTests {
    // 2026-07-06 is a Monday.
    @Test func countsWorkingDaysWithHolidaysAndHalfDays() {
        let models = [model()]
        #expect(FormCalendar.workingDays(from: "2026-07-06", to: "2026-07-17", models: models, holidays: []) == 10)
        #expect(FormCalendar.workingDays(from: "2026-07-06", to: "2026-07-17", models: models, holidays: [holiday("2026-07-08")]) == 9)
        #expect(FormCalendar.workingDays(from: "2026-07-06", to: "2026-07-17", models: models, holidays: [], halfDayStart: true, halfDayEnd: true) == 9)
        #expect(FormCalendar.workingDays(from: "2026-07-06", to: "2026-07-06", models: models, holidays: [], halfDayStart: true, halfDayEnd: true) == 0.5) // counted once
        #expect(FormCalendar.workingDays(from: "2026-07-11", to: "2026-07-11", models: models, holidays: [], halfDayStart: true) == 0) // weekend: no deduction
    }

    @Test func schoolHolidaysDoNotFreeADay() {
        #expect(FormCalendar.freeReason("2026-07-08", models: [model()], holidays: [holiday("2026-07-08", kind: .schoolHoliday)]) == nil)
        #expect(FormCalendar.freeReason("2026-07-08", models: [model()], holidays: [holiday("2026-07-08")]) == .holiday)
    }

    @Test func workModelDecidesWhichWeekdaysAreFree() {
        let fourDays = [model(workdays: [1, 2, 3, 4])]
        #expect(FormCalendar.freeReason("2026-07-10", models: fourDays, holidays: []) == .nonWorking) // Friday
        #expect(FormCalendar.freeReason("2026-07-11", models: fourDays, holidays: []) == .weekend)
        let zeroTarget = [model(daily: ["3": 0])]
        #expect(FormCalendar.freeReason("2026-07-08", models: zeroTarget, holidays: []) == .nonWorking) // Wednesday with a target of 0
        #expect(FormCalendar.freeReason("2026-07-11", models: [], holidays: []) == .weekend) // no model: Monday to Friday
        #expect(FormCalendar.freeReason("2026-07-10", models: [], holidays: []) == nil)
    }

    @Test func theModelValidOnTheDayWins() {
        let old = model("2025-01-01", validTo: "2026-06-30", workdays: [1, 2, 3, 4, 5])
        let new = model("2026-07-01", workdays: [1, 2, 3, 4])
        #expect(FormCalendar.freeReason("2026-06-26", models: [old, new], holidays: []) == nil) // Friday under the old model
        #expect(FormCalendar.freeReason("2026-07-10", models: [old, new], holidays: []) == .nonWorking) // Friday under the new one
    }

    @Test func freeDaysMergeIntoRanges() {
        let ranges = FormCalendar.ranges(of: ["2026-07-11", "2026-07-12", "2026-07-08", "2026-07-18", "2026-07-12"])
        #expect(ranges == [FormDayRange(from: "2026-07-08", to: "2026-07-08"), FormDayRange(from: "2026-07-11", to: "2026-07-12"), FormDayRange(from: "2026-07-18", to: "2026-07-18")])
        let fit = FormCalendar.fit(ranges, slots: 2)
        #expect(fit.shown.count == 2 && fit.overflow == [FormDayRange(from: "2026-07-18", to: "2026-07-18")])
        #expect(FormCalendar.fit(ranges, slots: 0).overflow.count == 3)
    }

    @Test func requestDataFollowsBalanceSemantics() {
        let balance = VacationBalance(year: 2026, entitlementHalfDays: 60, carryOverHalfDays: 4, adjustmentHalfDays: 2, bookedHalfDays: 10, plannedHalfDays: 20,
                                      availableHalfDays: 56, availableAfterPlannedHalfDays: 36)
        var inputs = FormRequestInputs(from: "2026-07-06", to: "2026-07-17", today: "2026-06-01", balance: balance, models: [model()],
                                       holidays: [holiday("2026-07-08")], inBalance: true)
        let data = FormRequestData(inputs)
        #expect(data.workingDays == 9)
        #expect(data.entitlementYearHalfDays == 60 && data.entitlementTotalHalfDays == 66) // 60 + 4 + 2
        #expect(data.restBeforeHalfDays == 36 + 18 && data.restAfterHalfDays == 36) // the request already counts in the balance
        #expect(data.freeRanges.map(\.from) == ["2026-07-08", "2026-07-11"] && data.freeRanges[1].to == "2026-07-12")
        inputs.inBalance = false
        let notInBalance = FormRequestData(inputs)
        #expect(notInBalance.restBeforeHalfDays == 36 && notInBalance.restAfterHalfDays == 18)
        // With a snapshot the stored remaining days replace entitlement and carry-over.
        inputs.balance = VacationBalance(year: 2026, snapshotDate: "2026-03-01", snapshotRemainingHalfDays: 40, entitlementHalfDays: 60, carryOverHalfDays: 4,
                                         adjustmentHalfDays: 2, availableHalfDays: 40, availableAfterPlannedHalfDays: 30)
        let snap = FormRequestData(inputs)
        #expect(snap.entitlementYearHalfDays == 40 && snap.entitlementTotalHalfDays == 42)
    }
}

struct FormResolveTests {
    private func data() -> FormRequestData {
        var request = FormRequestData(from: "2026-07-06", to: "2026-07-17", today: "2026-06-01")
        request.workingDays = 9.5
        request.substitute = "  Erika  "
        request.entitlementYearHalfDays = 60
        request.entitlementTotalHalfDays = 65
        request.carryOverHalfDays = 4
        request.adjustmentHalfDays = -3
        request.restBeforeHalfDays = 41
        request.restAfterHalfDays = 22
        request.freeRanges = [FormDayRange(from: "2026-07-08", to: "2026-07-08"), FormDayRange(from: "2026-07-11", to: "2026-07-12")]
        return request
    }

    private func mapping() -> FormMapping {
        var mapping = FormMapping()
        mapping.person = FormPerson(lastName: "Muster", firstName: "Max", personnelNo: " ", department: "IT", place: "Köln")
        return mapping
    }

    @Test func personAndFixedSources() {
        let m = mapping(), r = data()
        #expect(m.resolve(FormBinding(source: .fullName), r) == .text("Max Muster"))
        #expect(m.resolve(FormBinding(source: .personnelNo), r) == .empty) // blank stays empty
        #expect(m.resolve(FormBinding(source: .fixedText, text: " Fest "), r) == .text("Fest"))
        #expect(m.resolve(FormBinding(source: .fixedCheckbox, checked: true), r) == .flag(true))
        #expect(m.resolve(FormBinding(source: .fixedCheckbox), r) == .flag(false))
        #expect(m.resolve(FormBinding(source: .substitute), r) == .text("Erika"))
    }

    @Test func balanceSourcesUseGermanHalfDays() {
        let m = mapping(), r = data()
        #expect(m.resolve(FormBinding(source: .entitlementTotal), r) == .text("32,5"))
        #expect(m.resolve(FormBinding(source: .entitlementYear), r) == .text("30"))
        #expect(m.resolve(FormBinding(source: .carryOver), r) == .text("2"))
        #expect(m.resolve(FormBinding(source: .additional), r) == .text("0")) // negative correction is not "additional"
        #expect(m.resolve(FormBinding(source: .paidOut), r) == .text("1,5"))
        #expect(m.resolve(FormBinding(source: .restBefore), r) == .text("20,5"))
        #expect(m.resolve(FormBinding(source: .restAfter), r) == .text("11"))
        #expect(m.resolve(FormBinding(source: .workingDays), r) == .text("9,5"))
    }

    @Test func dateSourcesHonourBindingAndProfileFormats() {
        var m = mapping()
        let r = data()
        #expect(m.resolve(FormBinding(source: .dateFrom), r) == .text("06.07.2026"))
        #expect(m.resolve(FormBinding(source: .dateTo, dateFormat: .iso), r) == .text("2026-07-17"))
        #expect(m.resolve(FormBinding(source: .dateRange), r) == .text("06.07.2026 - 17.07.2026"))
        #expect(m.resolve(FormBinding(source: .today), r) == .text("01.06.2026"))
        m.dateFormat = .shortDotted
        #expect(m.resolve(FormBinding(source: .dateFrom), r) == .text("6.7.26"))
        var single = r
        single.to = single.from
        #expect(m.resolve(FormBinding(source: .dateRange), single) == .text("6.7.26")) // one day: no range
    }

    @Test func freeRangeSourcesAreAddressedByPosition() {
        let m = mapping(), r = data()
        #expect(m.resolve(FormBinding(source: .freeRange, index: 1), r) == .text("08.07.2026"))
        #expect(m.resolve(FormBinding(source: .freeRange, index: 2), r) == .text("11.07.2026 - 12.07.2026"))
        #expect(m.resolve(FormBinding(source: .freeRangeFrom, index: 2), r) == .text("11.07.2026"))
        #expect(m.resolve(FormBinding(source: .freeRangeTo, index: 2), r) == .text("12.07.2026"))
        #expect(m.resolve(FormBinding(source: .freeRange, index: 3), r) == .empty) // no third range
        #expect(m.resolve(FormBinding(source: .freeRangeFrom), r) == .text("08.07.2026")) // missing index means 1
        #expect(m.resolve(FormBinding(source: .freeDaysCount), r) == .text("3")) // calendar days of all ranges
        #expect(m.resolve(FormBinding(source: .hasFreeDays), r) == .flag(true))
        var none = r
        none.freeRanges = []
        #expect(m.resolve(FormBinding(source: .hasFreeDays), none) == .flag(false))
        #expect(m.resolve(FormBinding(source: .freeDaysCount), none) == .text("0"))
    }
}

#if canImport(PDFKit)
struct FormPDFTests {
    private func request() -> FormRequestData {
        var request = FormRequestData(from: "2026-07-06", to: "2026-07-17", today: "2026-06-01")
        request.workingDays = 10
        request.substitute = "Erika Beispiel"
        request.freeRanges = [FormDayRange(from: "2026-07-11", to: "2026-07-12")]
        return request
    }

    private func template() -> Data {
        SyntheticFormPDF.make(fields: [
            .init(name: "Name", kind: .text, rect: [50, 700, 250, 720]),
            .init(name: "Von", kind: .text, rect: [50, 670, 250, 690]),
            .init(name: "Bis", kind: .text, rect: [50, 640, 250, 660]),
            .init(name: "Frei", kind: .checkbox, rect: [50, 610, 70, 630]),
            .init(name: "Art", kind: .dropdown, rect: [50, 580, 250, 600], options: ["Erholungsurlaub", "Sonderurlaub"]),
            .init(name: "Gesperrt", kind: .text, rect: [50, 550, 250, 570], readOnly: true),
            .init(name: "Unterschrift", kind: .signature, rect: [50, 500, 250, 530]),
            .init(name: "Unbelegt", kind: .text, rect: [50, 470, 250, 490]),
            .init(name: "erste", kind: .text, rect: [50, 440, 250, 460], parent: "Zeile"),
        ])
    }

    private func mapping() -> FormMapping {
        var mapping = FormMapping()
        mapping.person = FormPerson(lastName: "Muster", firstName: "Max")
        mapping.fields = [
            "Name": FormBinding(source: .fullName), "Von": FormBinding(source: .dateFrom), "Bis": FormBinding(source: .dateTo),
            "Frei": FormBinding(source: .hasFreeDays), "Art": FormBinding(source: .fixedText, text: "Erholungsurlaub"),
            "Gesperrt": FormBinding(source: .fixedText, text: "darf nicht"), "Unterschrift": FormBinding(source: .fixedText, text: "darf nicht"),
            "Zeile.erste": FormBinding(source: .substitute),
        ]
        return mapping
    }

    @Test func inspectListsFieldsWithKindsAndQualifiedNames() throws {
        let info = try FormPDF.inspect(template())
        #expect(info.pageCount == 1)
        let byName = Dictionary(uniqueKeysWithValues: info.fields.map { ($0.name, $0) })
        #expect(byName["Name"]?.kind == .text && byName["Frei"]?.kind == .checkbox && byName["Art"]?.kind == .dropdown)
        #expect(byName["Art"]?.options == ["Erholungsurlaub", "Sonderurlaub"])
        #expect(byName["Unterschrift"]?.kind == .other && byName["Gesperrt"]?.readOnly == true)
        #expect(byName["Zeile.erste"]?.kind == .text) // hierarchical fields are addressed as parent.child (like the PWA)
    }

    @Test func fillsTextCheckboxAndDropdownAndLeavesTheRestAlone() throws {
        let source = template()
        let result = try FormPDF.fill(template: source, mapping: mapping(), request: request())
        let values = try FormPDF.fieldValues(result.data)
        #expect(values["Name"] == "Max Muster" && values["Von"] == "06.07.2026" && values["Bis"] == "17.07.2026")
        #expect(values["Frei"] == "on" && values["Art"] == "Erholungsurlaub" && values["Zeile.erste"] == "Erika Beispiel")
        #expect(values["Gesperrt"] == "" && values["Unbelegt"] == "") // read-only and unmapped fields are untouched
        #expect(result.skipped.isEmpty && result.filledCount == 6)
        // The result is still a fillable form, and the template bytes were not modified.
        #expect(try FormPDF.inspect(result.data).fields.count == 9)
        #expect(source == template())
    }

    @Test func clearsATextFieldWhenTheValueIsEmpty() throws {
        var m = mapping()
        m.fields["Name"] = FormBinding(source: .personnelNo) // blank in the profile
        let values = try FormPDF.fieldValues(FormPDF.fill(template: template(), mapping: m, request: request()).data)
        #expect(values["Name"] == "")
    }

    @Test func uncheckedWhenNoFreeDays() throws {
        var r = request()
        r.freeRanges = []
        let values = try FormPDF.fieldValues(FormPDF.fill(template: template(), mapping: mapping(), request: r).data)
        #expect(values["Frei"] == "off")
    }

    @Test func dropdownValueMustBeOffered() throws {
        var m = mapping()
        m.fields["Art"] = FormBinding(source: .fixedText, text: "Gibt es nicht")
        let result = try FormPDF.fill(template: template(), mapping: m, request: request())
        #expect(result.skipped == ["Art"])
        #expect(try FormPDF.fieldValues(result.data)["Art"] != "Gibt es nicht")
    }

    @Test func flatteningWritesTheValuesIntoThePageAndRemovesTheFields() throws {
        let result = try FormPDF.fill(template: template(), mapping: mapping(), request: request(), flatten: true)
        #expect(try FormPDF.inspect(result.data).fields.isEmpty)
        let text = FormPDF.text(result.data) ?? ""
        #expect(text.contains("Synthetic vacation request") && text.contains("Max Muster") && text.contains("06.07.2026") && text.contains("Erholungsurlaub"))
        // `mapping.flatten` is the default, the argument overrides it.
        var m = mapping()
        m.flatten = true
        #expect(try FormPDF.inspect(FormPDF.fill(template: template(), mapping: m, request: request()).data).fields.isEmpty)
        #expect(try FormPDF.inspect(FormPDF.fill(template: template(), mapping: m, request: request(), flatten: false).data).fields.count == 9)
    }

    @Test func overlaysDrawTextOnAFlatTemplate() throws {
        var m = FormMapping()
        m.overlays = [
            FormOverlay(id: "a", page: 0, x: 100, y: 500, fontSize: 12, binding: FormBinding(source: .dateRange)),
            FormOverlay(id: "b", page: 7, x: 10, y: 10, binding: FormBinding(source: .today)), // page does not exist: ignored
            FormOverlay(id: "c", page: 0, x: 100, y: 450, binding: FormBinding(source: .lastName)), // empty value: ignored
        ]
        let flat = SyntheticFormPDF.flat()
        let result = try FormPDF.fill(template: flat, mapping: m, request: request(), flatten: true)
        #expect(result.filledCount == 1)
        #expect((FormPDF.text(result.data) ?? "").contains("06.07.2026 - 17.07.2026"))
        // Without flattening the overlay stays a free-text annotation (printable, selectable); the template has no fields.
        let editable = try FormPDF.fill(template: flat, mapping: m, request: request(), flatten: false)
        #expect(try FormPDF.inspect(editable.data).fields.isEmpty)
        let annotations = PDFDocument(data: editable.data)?.page(at: 0)?.annotations ?? []
        #expect(annotations.map { $0.contents ?? "" } == ["06.07.2026 - 17.07.2026"] && annotations.first?.shouldPrint == true)
    }

    @Test func multiPageTemplatesKeepAllPages() throws {
        let pdf = SyntheticFormPDF.make(fields: [.init(name: "Name", kind: .text), .init(name: "Seite2", kind: .text, page: 1)], pageCount: 3)
        var m = FormMapping()
        m.fields = ["Name": FormBinding(source: .fixedText, text: "A"), "Seite2": FormBinding(source: .fixedText, text: "B")]
        for flatten in [false, true] {
            let result = try FormPDF.fill(template: pdf, mapping: m, request: request(), flatten: flatten)
            #expect(PDFDocument(data: result.data)?.pageCount == 3)
        }
        let info = try FormPDF.inspect(pdf)
        #expect(info.fields.first { $0.name == "Seite2" }?.page == 2)
    }

    @Test func rejectsUnusableTemplates() throws {
        #expect(throws: FormPDFProblem.empty) { try FormPDF.fill(template: Data(), mapping: mapping(), request: request()) }
        #expect(throws: FormPDFProblem.notPDF) { try FormPDF.fill(template: Data("hello".utf8), mapping: mapping(), request: request()) }
        #expect(throws: FormPDFProblem.tooLarge) {
            try FormPDF.fill(template: Data("%PDF-1.7".utf8) + Data(count: FormPDFLimits.maxBytes), mapping: mapping(), request: request())
        }
        #expect(throws: FormPDFProblem.unreadable) { try FormPDF.fill(template: Data("%PDF-1.7 garbage".utf8), mapping: mapping(), request: request()) }
        #expect(FormPDFLimits.hasPDFMagic(Data("junk".utf8) + Data("%PDF-1.4".utf8)))
        #expect(!FormPDFLimits.hasPDFMagic(Data(count: 1100) + Data("%PDF-1.4".utf8))) // magic only counts in the first 1024 bytes
    }

    @Test func rejectsPasswordProtectedTemplates() throws {
        let output = NSMutableData()
        let consumer = CGDataConsumer(data: output as CFMutableData)!
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let info = [kCGPDFContextUserPassword: "geheim", kCGPDFContextOwnerPassword: "geheim"] as CFDictionary
        let context = CGContext(consumer: consumer, mediaBox: &box, info)!
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        #expect(throws: FormPDFProblem.encrypted) { try FormPDF.fill(template: output as Data, mapping: mapping(), request: request()) }
    }
}
#endif

@MainActor
struct VacationRequestStoreTests {
    private let absenceId = UUID(uuidString: "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa")!
    private let fileId = "cccccccc-0000-4000-8000-000000000009"

    private func absence(status: AbsenceStatus = .planned) -> Absence {
        Absence(id: absenceId, kind: .vacation, startDate: "2026-07-06", endDate: "2026-07-17", status: status, countedHalfDays: 20)
    }

    private static let balanceJSON = #"{"year":2026,"entitlementHalfDays":60,"carryOverHalfDays":0,"adjustmentHalfDays":0,"bookedHalfDays":0,"plannedHalfDays":20,"availableHalfDays":60,"availableAfterPlannedHalfDays":40}"#

    private func prepared(_ transport: MockTransport, mapping: String = #"{"person":{"firstName":"Max","lastName":"Muster"},"fields":{"Name":{"source":"fullName"},"Von":{"source":"dateFrom"},"Frei":{"source":"freeRange","index":1}}}"#) -> VacationRequestStore {
        transport.set("GET /api/v1/vacation/request-form", body: #"{"exists":true,"fileName":"Antrag.pdf","sizeBytes":1000,"mapping":\#(mapping),"updatedAt":"2026-10-20T08:00:00Z"}"#)
        transport.set("GET /api/v1/vacation/balance", body: Self.balanceJSON)
        transport.set("GET /api/v1/work-models", body: Fixtures.workModelJSON)
        transport.set("GET /api/v1/calendar/holidays", body: "[]")
        transport.set("GET /api/v1/vacation/request-form/file", body: String(decoding: SyntheticFormPDF.make(fields: [.init(name: "Name", kind: .text)]), as: UTF8.self))
        return VacationRequestStore(client: Fixtures.client(transport), absence: absence(), today: "2026-06-01")
    }

    @Test func loadsTemplateBalanceAndCalendarForTheSpan() async {
        let transport = MockTransport()
        let store = prepared(transport)
        await store.load()
        #expect(store.phase == .ready)
        #expect(store.request?.workingDays == 10 && store.request?.restBeforeHalfDays == 60 && store.request?.restAfterHalfDays == 40)
        #expect(store.freeRangeSlots == 1 && store.mappedFieldCount == 3)
        #expect(store.freeRangeFit.shown.map(\.from) == ["2026-07-11"] && store.freeRangeFit.overflow.isEmpty)
        #expect(transport.requests(matching: "GET /api/v1/vacation/balance").first?.url?.query == "year=2026")
        #expect(transport.requests(matching: "GET /api/v1/vacation/request-form/file").first?.value(forHTTPHeaderField: "Accept") == "application/pdf")
    }

    @Test func noTemplateIsAStateNotAnError() async {
        let transport = MockTransport()
        transport.set("GET /api/v1/vacation/request-form", body: #"{"exists":false,"fileName":null,"sizeBytes":null,"mapping":null,"updatedAt":null}"#)
        let store = VacationRequestStore(client: Fixtures.client(transport), absence: absence(), today: "2026-06-01")
        await store.load()
        #expect(store.phase == .noTemplate)
        #expect(transport.requests(matching: "GET /api/v1/vacation/request-form/file").isEmpty)
        // A file that went missing between the two calls is the same state.
        let second = MockTransport()
        _ = prepared(second)
        second.set("GET /api/v1/vacation/request-form/file", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        let other = VacationRequestStore(client: Fixtures.client(second), absence: absence(), today: "2026-06-01")
        await other.load()
        #expect(other.phase == .noTemplate)
    }

    @Test func loadFailureIsReported() async {
        let transport = MockTransport()
        transport.set("GET /api/v1/vacation/request-form", error: .notConnectedToInternet)
        let store = VacationRequestStore(client: Fixtures.client(transport), absence: absence(), today: "2026-06-01")
        await store.load()
        #expect(store.phase == .failed(.network(.notConnectedToInternet)))
    }

    #if canImport(PDFKit)
    @Test func generatesThePDFAndAttachesItToTheAbsence() async throws {
        let transport = MockTransport()
        let store = prepared(transport)
        let pdf = SyntheticFormPDF.make(fields: [.init(name: "Name", kind: .text), .init(name: "Von", kind: .text, rect: [50, 660, 250, 680]), .init(name: "Frei", kind: .text, rect: [50, 620, 250, 640])])
        transport.set("GET /api/v1/vacation/request-form/file", body: String(decoding: pdf, as: UTF8.self))
        // The mock body is a String; a binary PDF would not survive, so serve this one as ASCII (the synthetic PDF is plain text).
        await store.load()
        #expect(store.phase == .ready)
        store.substitute = "Erika"
        await store.generate()
        let generated = try #require(store.generated)
        #expect(generated.fileName == "Urlaubsantrag_2026-07-06_2026-07-17.pdf" && generated.filledCount == 3)
        let values = try FormPDF.fieldValues(generated.data)
        #expect(values["Name"] == "Max Muster" && values["Von"] == "06.07.2026" && values["Frei"] == "11.07.2026 - 12.07.2026")

        // Changing an input invalidates the result.
        store.freeConfirmed = false
        #expect(store.generated == nil)
        await store.generate()
        #expect(try FormPDF.fieldValues(#require(store.generated).data)["Frei"] == "")

        transport.set("POST /api/v1/files", status: 201, body: #"{"id":"\#(fileId)","name":"Urlaubsantrag_2026-07-06_2026-07-17.pdf","size":1,"sha256":"x","contentType":"application/pdf","createdAt":"2026-06-01T08:00:00Z"}"#)
        transport.set("POST /api/v1/absences/\(absenceId.uuidString.lowercased())/attachments", status: 201, body: #"{"id":"\#(fileId)","name":"a.pdf","size":1,"sha256":"x","contentType":"application/pdf","createdAt":"2026-06-01T08:00:00Z"}"#)
        await store.saveAsAttachment()
        #expect(store.attachState == .saved)
        let upload = String(decoding: transport.requests(matching: "POST /api/v1/files").first?.httpBody ?? Data(), as: UTF8.self)
        #expect(upload.contains("filename=\"Urlaubsantrag_2026-07-06_2026-07-17.pdf\"") && upload.contains("Content-Type: application/pdf") && upload.contains("%PDF-"))
    }

    @Test func attachingFailureDeletesTheOrphanedUpload() async throws {
        let transport = MockTransport()
        let store = prepared(transport)
        transport.set("GET /api/v1/vacation/request-form/file", body: String(decoding: SyntheticFormPDF.make(fields: [.init(name: "Name", kind: .text)]), as: UTF8.self))
        await store.load()
        await store.generate()
        #expect(store.generated != nil)
        transport.set("POST /api/v1/files", status: 201, body: #"{"id":"\#(fileId)","name":"a.pdf","size":1,"sha256":"x","contentType":"application/pdf","createdAt":"2026-06-01T08:00:00Z"}"#)
        transport.set("POST /api/v1/absences/\(absenceId.uuidString.lowercased())/attachments", status: 404, body: #"{"error":{"code":"not_found","message":"x"}}"#)
        transport.set("DELETE /api/v1/files/\(fileId)", status: 204)
        await store.saveAsAttachment()
        guard case .failed = store.attachState else { Issue.record("expected a failure"); return }
        #expect(transport.requests(matching: "DELETE /api/v1/files/\(fileId)").count == 1)
    }

    @Test func unusableTemplateIsReportedAtGeneration() async {
        let transport = MockTransport()
        let store = prepared(transport)
        transport.set("GET /api/v1/vacation/request-form/file", body: "not a pdf")
        await store.load()
        await store.generate()
        #expect(store.generated == nil && store.generationProblem == .notPDF)
    }
    #endif
}
