import Foundation
import Testing
@testable import TimetrackCore

@Suite struct SupportTests {
    @Test func durationFormatting() {
        #expect(DurationFormat.hoursMinutes(27720) == "7:42")
        #expect(DurationFormat.hoursMinutes(-1080) == "-0:18")
        #expect(DurationFormat.hoursMinutes(-30) == "0:00")
        #expect(DurationFormat.signed(600) == "+0:10")
        #expect(DurationFormat.signed(-600) == "-0:10")
        #expect(DurationFormat.clock(3725) == "1:02:05")
        #expect(DurationFormat.clock(-5) == "0:00:00")
    }

    @Test func durationParsing() {
        #expect(DurationFormat.parse("7:42") == 27720)
        #expect(DurationFormat.parse("-0:18") == -1080)
        #expect(DurationFormat.parse("+1:05") == 3900)
        #expect(DurationFormat.parse("45") == 2700)
        #expect(DurationFormat.parse("7,7") == nil)
        #expect(DurationFormat.parse("1:75") == nil)
    }

    @Test func runningTimerTicks() {
        let start = Date(timeIntervalSince1970: 1000)
        let display = RunningTimerDisplay(startedAt: start)
        #expect(display.clock(at: start.addingTimeInterval(65)) == "0:01:05")
        #expect(display.elapsedSeconds(at: start.addingTimeInterval(-10)) == 0)
    }

    @Test func localDayArithmetic() {
        #expect(LocalDays.adding(1, to: "2026-02-28") == "2026-03-01")
        #expect(LocalDays.adding(-1, to: "2026-01-01") == "2025-12-31")
        #expect(LocalDays.isoWeekday("2026-10-16") == 5) // Friday
        #expect(LocalDays.mondayOfWeek(containing: "2026-10-18") == "2026-10-12")
        #expect(LocalDays.parse("2026-02-30") == nil)
        #expect(LocalDays.daysBetween("2026-10-01", "2026-10-16") == 15)
    }

    @Test func dayCalendarHandlesDST() throws {
        let berlin = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let interval = try #require(berlin.interval(of: "2026-10-25")) // DST ends: 25 hours
        #expect(interval.end.timeIntervalSince(interval.start) == 25 * 3600)
        #expect(berlin.day(for: Date(timeIntervalSince1970: 1_792_130_820)) == "2026-10-16")
        let instant = try #require(berlin.instant(day: "2026-10-16", hour: 8, minute: 7))
        #expect(JSONCoding.formatInstant(instant) == "2026-10-16T06:07:00Z")
    }

    @Test func base64URLRoundTrip() {
        let data = Data([0xfb, 0xff, 0xfe, 0x01])
        let text = Base64URL.encode(data)
        #expect(!text.contains("+") && !text.contains("/") && !text.contains("="))
        #expect(Base64URL.decode(text) == data)
    }

    @Test func jsonValueRoundTrip() throws {
        let value = JSONValue.object(["a": .array([.number(1), .string("x"), .null, .bool(true)])])
        let decoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
    }

    @Test func inMemorySecretStore() {
        let store = InMemorySecretStore()
        store.write("v", for: "k")
        #expect(store.read("k") == "v")
        store.delete("k")
        #expect(store.read("k") == nil)
    }
}
