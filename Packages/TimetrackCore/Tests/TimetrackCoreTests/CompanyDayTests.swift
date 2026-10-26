import Foundation
import Testing
@testable import TimetrackCore

// N4 (contract 0.32.0, ADR-0029): company days in settings, week days and the holiday list.
@Suite("Company days")
struct CompanyDayTests {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()

    private let settingsJSON = """
    {"configured":true,"region":"DE-ST","annualEntitlementHalfDays":60,"carryOverByYear":{"2026":8},"carryOverExpiry":"03-31",
     "companyDays":[{"month":12,"day":24,"treatment":"half","name":"Heiligabend"},
                    {"month":12,"day":31,"treatment":"full","name":"Silvester"},
                    {"month":6,"day":12,"treatment":"future-mode","name":null}]}
    """

    @Test func decodesSettingsWithCompanyDays() throws {
        let settings = try decoder.decode(VacationSettings.self, from: Data(settingsJSON.utf8))
        #expect(settings.companyDays?.count == 3)
        #expect(settings.companyDays?[0].treatment == .half)
        #expect(settings.companyDays?[1].treatment == .full)
        #expect(settings.companyDays?[2].treatment == .other("future-mode"))
    }

    @Test func roundTripKeepsCompanyDaysAndUnknownTreatment() throws {
        var settings = try decoder.decode(VacationSettings.self, from: Data(settingsJSON.utf8))
        settings.annualEntitlementHalfDays = 62
        let object = try #require(JSONSerialization.jsonObject(with: encoder.encode(settings)) as? [String: Any])
        #expect(object["annualEntitlementHalfDays"] as? Int == 62)
        let rules = try #require(object["companyDays"] as? [[String: Any]])
        #expect(rules.count == 3)
        #expect(rules[2]["treatment"] as? String == "future-mode")
        #expect(rules[2]["name"] is NSNull)
        #expect(rules[0]["name"] as? String == "Heiligabend")
        #expect(object["configured"] == nil)
    }

    @Test func putWithoutCompanyDaysLeavesFieldOut() throws {
        let settings = try decoder.decode(VacationSettings.self, from: Data(#"{"region":"DE-ST","annualEntitlementHalfDays":60,"carryOverExpiry":null}"#.utf8))
        #expect(settings.companyDays == nil)
        let object = try #require(JSONSerialization.jsonObject(with: encoder.encode(settings)) as? [String: Any])
        #expect(object["companyDays"] == nil)
    }

    @Test func blankNameIsSentAsNull() throws {
        let data = try encoder.encode(CompanyDayRule(month: 6, day: 12, treatment: .half, name: "  "))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["name"] is NSNull)
    }

    @Test func decodesWeekDayCompanyFields() throws {
        let half = try decoder.decode(TimeWeekDayFieldsProbe.self, from: Data(#"{"holidayName":"Heiligabend","companyDayTreatment":"half"}"#.utf8))
        #expect(CompanyDayText.title(name: half.holidayName ?? "", treatment: half.companyDayTreatment) == "Heiligabend (halber Tag)")
        let full = try decoder.decode(TimeWeekDayFieldsProbe.self, from: Data(#"{"holidayName":"Silvester","companyDayTreatment":"full"}"#.utf8))
        #expect(CompanyDayText.title(name: full.holidayName ?? "", treatment: full.companyDayTreatment) == "Silvester")
        let plain = try decoder.decode(TimeWeekDayFieldsProbe.self, from: Data("{}".utf8))
        #expect(plain.holidayName == nil && plain.companyDayTreatment == nil)
    }

    @Test func decodesFullWeekDayAndHolidayLabel() throws {
        let json = """
        {"date":"2026-12-24","weekday":4,"mark":"work","targetSeconds":14400,"plannedSeconds":null,"planMode":null,"workSeconds":0,"creditSeconds":0,
         "rawWorkSeconds":0,"breakSeconds":0,"breakDeductionSeconds":0,"travelSeconds":0,"schoolSeconds":0,"balanceSeconds":null,"firstStart":null,
         "lastEnd":null,"segmentsCount":0,"absences":[],"provisional":false,"isToday":false,"isFuture":true,"holidayName":"Heiligabend","companyDayTreatment":"half"}
        """
        let day = try decoder.decode(TimeWeekDay.self, from: Data(json.utf8))
        #expect(day.mark == .work)
        #expect(day.holidayLabel == "Heiligabend (halber Tag)")
        let older = json.replacingOccurrences(of: #","holidayName":"Heiligabend","companyDayTreatment":"half""#, with: "")
        #expect(try decoder.decode(TimeWeekDay.self, from: Data(older.utf8)).holidayLabel == nil)
    }

    @Test func calendarDayHalfVariant() throws {
        let json = #"[{"id":null,"startDate":"2026-12-24","endDate":"2026-12-24","name":"Heiligabend","kind":"holiday","source":"builtin","companyTreatment":"half"},{"id":null,"startDate":"2026-12-25","endDate":"2026-12-25","name":"1. Weihnachtstag","kind":"holiday","source":"builtin","companyTreatment":null},{"startDate":"2026-12-31","endDate":"2026-12-31","name":"Silvester","kind":"holiday","source":"builtin","companyTreatment":"full"}]"#
        let days = try decoder.decode([CalendarDay].self, from: Data(json.utf8))
        #expect(days[0].isHalfDay && days[0].displayName == "Heiligabend (halber Tag)")
        #expect(!days[1].isHalfDay && days[1].displayName == "1. Weihnachtstag")
        #expect(!days[2].isHalfDay && days[2].displayName == "Silvester" && days[2].kind == .holiday)
    }

    @Test func normalizedAlwaysListsBuiltInSlots() {
        let own = CompanyDayRule(month: 6, day: 12, treatment: .full, name: "Betriebsausflug")
        let list = CompanyDayRules.normalized([own])
        #expect(list.map(\.id) == ["06-12", "12-24", "12-31"])
        #expect(CompanyDayRules.normalized(nil) == CompanyDayRules.defaults)
        #expect(CompanyDayRules.ownRules(list) == [own])
        #expect(list[1].displayName == "Heiligabend" && list[2].displayName == "Silvester")
        #expect(CompanyDayRule(month: 3, day: 1, treatment: .half).displayName == "Betriebsfreier Tag")
    }

    @Test func settingTreatmentChangesOnlyThatRule() {
        let list = CompanyDayRules.setting(.half, month: 12, day: 24, in: CompanyDayRules.defaults)
        #expect(list[0].treatment == .half)
        #expect(list[1].treatment == .none)
    }

    @Test func parsesDatesAndValidatesNewRules() {
        #expect(CompanyDayRules.parseDate("12.06.")?.month == 6)
        #expect(CompanyDayRules.parseDate("31.04.") == nil)
        #expect(CompanyDayRules.parseDate("xx") == nil)
        let rules = CompanyDayRules.defaults
        #expect(CompanyDayRules.problem(adding: 2, day: 29, name: nil, to: rules) == .leapDay)
        #expect(CompanyDayRules.problem(adding: 12, day: 24, name: nil, to: rules) == .duplicate)
        #expect(CompanyDayRules.problem(adding: 6, day: 12, name: String(repeating: "x", count: 81), to: rules) == .nameTooLong)
        #expect(CompanyDayRules.problem(adding: 6, day: 12, name: "Ausflug", to: rules) == nil)
        let full = (1...12).map { CompanyDayRule(month: $0, day: 1, treatment: .half) }
        #expect(CompanyDayRules.problem(adding: 6, day: 12, name: nil, to: full) == .tooMany)
    }

    @Test func halfDayIsNotAFullHolidayInCalendarInfo() {
        // Display rule used by the month grid: only non-half entries make a cell a holiday.
        let half = CalendarDay(startDate: "2026-12-24", endDate: "2026-12-24", name: "Heiligabend", kind: .holiday, source: .builtin, companyTreatment: .half)
        let full = CalendarDay(startDate: "2026-12-31", endDate: "2026-12-31", name: "Silvester", kind: .holiday, source: .builtin, companyTreatment: .full)
        #expect([half].contains { !$0.isHalfDay } == false)
        #expect([full].contains { !$0.isHalfDay })
    }
}

/// The two new week-day fields in isolation.
private struct TimeWeekDayFieldsProbe: Decodable {
    let holidayName: String?
    let companyDayTreatment: CompanyDayTreatment?
}
