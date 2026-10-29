import Foundation
import Testing
@testable import TimetrackCore

@Suite("Q1 Live Activity tint")
struct LiveActivityTintTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    // A strongly saturated teal like the work accent of the user's screenshot.
    private let teal = (hue: 0.48, sat: 0.8, bri: 0.85)

    private func tint(_ style: LiveActivityTintStyle, dark: Bool = true) -> LiveActivityTintColor {
        LiveActivityTint.color(style: style, hue: teal.hue, saturation: teal.sat, brightness: teal.bri, dark: dark)
    }

    @Test func defaultIsSubtle() {
        #expect(LiveActivityTintStyle.default == .subtle)
        #expect(LiveActivityTintStyle.allCases.count == 3)
        #expect(LiveActivityTarget(kind: .work, startedAt: start).activeTintStyle == .subtle)
    }

    @Test func subtleIsDarkAndLowSaturation() {
        let subtle = tint(.subtle), colorful = tint(.colorful)
        #expect(subtle.brightness <= 0.12)
        #expect(subtle.saturation <= 0.5)
        #expect(subtle.saturation < colorful.saturation / 2)
        #expect(subtle.brightness < colorful.brightness)
        #expect(subtle.hue == teal.hue) // still a hint of the kind colour
    }

    @Test func subtleDarkIsAlmostTransparentButReadable() {
        // N2: dark and see-through, white text still readable over a mid grey and over a fairly bright backdrop.
        for style in [LiveActivityTintStyle.subtle, .neutral] {
            let color = tint(style)
            #expect(color.alpha <= 0.55, "\(style)")
            #expect(color.brightness <= 0.12, "\(style)")
            #expect(color.whiteTextContrast(overGrey: 0.34) >= 7, "\(style)")
            #expect(color.whiteTextContrast(overGrey: 0.62) >= 4.5, "\(style)")
        }
    }

    @Test func neutralHasNoHue() {
        #expect(tint(.neutral).saturation == 0)
        #expect(tint(.neutral, dark: false).saturation == 0)
    }

    @Test func whiteTextStaysReadableInEveryDarkStyle() {
        for style in LiveActivityTintStyle.allCases {
            #expect(tint(style).whiteTextContrast() >= 7, "\(style)") // AAA for white on the dark card
        }
    }

    @Test func subtleLightVariantStaysLight() {
        #expect(tint(.subtle, dark: false).brightness >= 0.9)
        #expect(tint(.subtle, dark: false).saturation <= 0.1)
    }

    @Test func oldStatesDecodeAndDefaultStoresNothing() throws {
        let old = #"{"kind":"work","startedAt":0,"workedSeconds":0}"#
        let decoded = try JSONDecoder().decode(LiveActivityTarget.self, from: Data(old.utf8))
        #expect(decoded.tintStyle == nil)
        #expect(decoded.activeTintStyle == .subtle)
    }

    @Test func desiredCarriesOnlyANonDefaultTint() {
        let snap = WidgetSnapshot(isRunning: true, kind: .work, startedAt: start, todaySeconds: 0, day: "2027-01-15", timeZone: "UTC", updatedAt: start)
        #expect(LiveActivityTarget.desired(snapshot: snap, pause: nil, now: start)?.tintStyle == nil)
        #expect(LiveActivityTarget.desired(snapshot: snap, pause: nil, tintStyle: .subtle, now: start)?.tintStyle == nil)
        #expect(LiveActivityTarget.desired(snapshot: snap, pause: nil, tintStyle: .colorful, now: start)?.tintStyle == .colorful)
        #expect(LiveActivityTarget.desired(snapshot: snap, pause: nil, tintStyle: .neutral, now: start)?.tintStyle == .neutral)
    }

    @Test func changingTheTintUpdatesInsteadOfRestarting() {
        let before = LiveActivityTarget(kind: .work, startedAt: start)
        let after = LiveActivityTarget(kind: .work, startedAt: start, tintStyle: .colorful)
        let plan = LiveActivityReconciler.plan(desired: after, existing: [LiveActivityExisting(id: "a", target: before)])
        #expect(plan.keep == "a")
        #expect(plan.update == after)
        #expect(plan.start == nil)
    }

    @Test func storeRoundTripAndUnknownValue() {
        let suite = "q1.test.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = LiveActivityTintStore(suiteName: suite)
        #expect(store.read() == .subtle)
        store.write(.neutral)
        #expect(store.read() == .neutral)
        UserDefaults(suiteName: suite)?.set("unicorn", forKey: LiveActivityTintStore.key)
        #expect(store.read() == .subtle)
    }

    @Test func watchCardIsOpaqueAndDarkForEveryStyle() {
        // LA7: the watch card must not depend on the appearance or on transparency; white text keeps >= 12:1 over any backdrop.
        for style in LiveActivityTintStyle.allCases {
            let color = LiveActivityTint.watchCard(style: style, hue: teal.hue, saturation: teal.sat, brightness: teal.bri)
            #expect(color.alpha == 1, "\(style)")
            #expect(color.brightness <= 0.22, "\(style)")
            #expect(color.whiteTextContrast(overGrey: 0.9) >= 12, "\(style)")
        }
        #expect(LiveActivityTint.watchCard(style: .subtle, hue: 0.48, saturation: 0.8, brightness: 0.85).hue == 0.48)
    }
}
