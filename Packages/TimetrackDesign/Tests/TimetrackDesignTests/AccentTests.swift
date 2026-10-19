import SwiftUI
import Testing
import TimetrackCore
@testable import TimetrackDesign

@MainActor
@Suite struct AccentTests {
    /// Every preset plus awkward custom colours (very light, very dark, saturated yellow, pure primaries).
    static let samples: [UInt32] = AccentChoice.allCases.compactMap(\.presetHex)
        + [0xFFFFFF, 0x000000, 0xFFFF00, 0x00FF00, 0xFF0000, 0x0000FF, 0x00FFFF, 0xFF00FF, 0x808080, 0xFBBF24, 0xA3E635, 0x93C5FD, 0x1E1B4B]

    @Test func contrastMathMatchesWCAG() {
        #expect(abs(AccentDerivation.contrast(0x000000, 0xFFFFFF) - 21) < 0.001)
        #expect(abs(AccentDerivation.contrast(0x777777, 0x777777) - 1) < 0.001)
        #expect(abs(AccentDerivation.contrast(0x2563EB, 0xFFFFFF) - 5.17) < 0.05)
    }

    @Test func parsesHex() {
        #expect(AccentDerivation.parse("#2563eb") == 0x2563EB)
        #expect(AccentDerivation.parse("2563EB") == 0x2563EB)
        #expect(AccentDerivation.parse("#abc") == 0xAABBCC)
        #expect(AccentDerivation.parse("#12345") == nil)
        #expect(AccentDerivation.parse("zzzzzz") == nil)
        #expect(AccentDerivation.string(0x0EA5A4) == "#0EA5A4")
    }

    @Test func inkReachesTextContrastOnAllSurfacesAndTints() {
        for hex in Self.samples {
            let tokens = AccentDerivation.tokens(for: hex)
            for (ink, surfaces) in [(tokens.inkLight, AccentDerivation.lightSurfaces), (tokens.inkDark, AccentDerivation.darkSurfaces)] {
                for background in surfaces.backgrounds {
                    #expect(AccentDerivation.contrast(ink, background) >= 4.5, "ink \(AccentDerivation.string(ink)) of \(AccentDerivation.string(hex)) on \(AccentDerivation.string(background))")
                    let tint = AccentDerivation.mix(hex, share: surfaces.tintShare, over: background)
                    #expect(AccentDerivation.contrast(ink, tint) >= 4.5, "ink \(AccentDerivation.string(ink)) of \(AccentDerivation.string(hex)) on tint \(AccentDerivation.string(tint))")
                }
            }
        }
    }

    @Test func textOnFillReachesTextContrast() {
        for hex in Self.samples {
            let tokens = AccentDerivation.tokens(for: hex)
            #expect(AccentDerivation.contrast(tokens.fillLight, tokens.onFillLight) >= 4.5, "light \(AccentDerivation.string(hex))")
            #expect(AccentDerivation.contrast(tokens.fillDark, tokens.onFillDark) >= 4.5, "dark \(AccentDerivation.string(hex))")
        }
    }

    @Test func darkFillStaysVisibleAgainstDarkSurfaces() {
        for hex in Self.samples where AccentDerivation.luminance(hex) > 0.0001 || hex == 0x000000 {
            let fill = AccentDerivation.tokens(for: hex).fillDark
            for background in [UInt32(0x0C0C0E), 0x1A1A1E] {
                #expect(AccentDerivation.contrast(fill, background) >= 3, "fill \(AccentDerivation.string(fill)) of \(AccentDerivation.string(hex))")
            }
        }
    }

    @Test func wellContrastedAccentsKeepTheirHue() {
        // Blue is the default accent: fill stays and ink in light mode stays close to the chosen colour.
        let blue = AccentDerivation.tokens(for: 0x2563EB)
        #expect(blue.fillLight == 0x2563EB)
        #expect(AccentDerivation.contrast(blue.inkLight, 0x2563EB) < 1.3)
        #expect(blue.onFillLight == 0xFFFFFF)
        // Orange cannot carry white text: black is chosen and the light ink is darkened.
        let orange = AccentDerivation.tokens(for: 0xF97316)
        #expect(orange.onFillLight == 0x000000)
        #expect(orange.inkLight != 0xF97316)
    }

    @Test func choiceResolvesHex() {
        #expect(AccentChoice.resolvedHex(choice: "orange", custom: "#112233") == "#F97316")
        #expect(AccentChoice.resolvedHex(choice: "custom", custom: "#112233") == "#112233")
        #expect(AccentChoice.resolvedHex(choice: "custom", custom: "bogus") == "#2563EB")
        #expect(AccentChoice.resolvedHex(choice: "unknown", custom: "#112233") == "#2563EB")
        #expect(SchemeChoice.system.colorScheme == nil)
        #expect(SchemeChoice.dark.colorScheme == .dark)
    }

    @Test func colorHexRoundTrip() {
        for hex in [UInt32(0x2563EB), 0x0EA5A4, 0xF97316, 0x52525B, 0x000000, 0xFFFFFF] {
            #expect(Color(hex: hex).ttHexString() == AccentDerivation.string(hex))
        }
    }
}

@Suite struct AccountAccentMappingTests {
    @Test func presetIdsMatchTheContract() {
        #expect(AccentChoice.allCases.map(\.rawValue) == AccentPreset.allCases.map(\.rawValue))
        #expect(SchemeChoice.allCases.map(\.rawValue) == ColorSchemePreference.allCases.map(\.rawValue))
    }

    @Test func effectiveHexResolvesPresetsAndCustom() {
        #expect(AppearanceKeys.effectiveHex(LocalAppearance(accent: "orange", customHex: "#112233", scheme: "system")) == "#F97316")
        #expect(AppearanceKeys.effectiveHex(LocalAppearance(accent: "custom", customHex: "#112233", scheme: "system")) == "#112233")
        #expect(AppearanceKeys.effectiveHex(LocalAppearance(accent: "magenta", customHex: "#112233", scheme: "system")) == "#A21CAF")
    }

    @Test func widgetInkKeepsContrastForEveryAccount­Preset() {
        // Widgets and the complication derive their colours from the snapshot hex exactly like the app does.
        for choice in AccentChoice.allCases {
            let hex = AccentChoice.resolvedHex(choice: choice.rawValue, custom: "#808080")
            let base = TTTheme(accentHex: hex).baseHex
            let tokens = AccentDerivation.tokens(for: base)
            for background in AccentDerivation.darkSurfaces.backgrounds {
                #expect(AccentDerivation.contrast(tokens.inkDark, background) >= AccentDerivation.minTextContrast, "\(choice) dark ink")
            }
            for background in AccentDerivation.lightSurfaces.backgrounds {
                #expect(AccentDerivation.contrast(tokens.inkLight, background) >= AccentDerivation.minTextContrast, "\(choice) light ink")
            }
            #expect(AccentDerivation.contrast(tokens.onFillLight, tokens.fillLight) >= AccentDerivation.minTextContrast, "\(choice) onFill")
        }
    }
}

@Suite struct AccentParityTests {
    /// Hues from docs/handoffs/AC2.md (backend) and the PWA's accent.ts; the six oldest keep their native values.
    static let darkFills: [String: UInt32] = [
        "indigo": 0x4338CA, "navy": 0x1E3A8A, "purple": 0x7E22CE, "magenta": 0xA21CAF, "crimson": 0xB91C1C, "forest": 0x166534,
        "petrol": 0x0F766E, "bronze": 0x92400E, "wine": 0x7F1D3F, "slate": 0x475A8C, "cocoa": 0x5C4033, "olive": 0x4D6B1F, "ocean": 0x0E7490, "ink": 0x334155,
    ]

    @Test func everyContractIdIsAChoiceWithAHue() {
        #expect(AccentChoice.allCases.count == 22)
        for (id, hex) in Self.darkFills { #expect(AccentChoice(rawValue: id)?.presetHex == hex, "\(id)") }
        #expect(AccentChoice.allCases.filter { $0.presetHex == nil } == [.custom])
        #expect(Set(AccentChoice.allCases.compactMap(\.presetHex)).count == 21, "hues are distinct")
    }

    @Test func darkPresetsCarryWhiteText() {
        for (id, hex) in Self.darkFills {
            let tokens = AccentDerivation.tokens(for: hex)
            #expect(tokens.onFillLight == 0xFFFFFF, "\(id) white on accent (light)")
            #expect(AccentDerivation.contrast(tokens.fillLight, 0xFFFFFF) >= 4.5, "\(id)")
            #expect(AccentDerivation.contrast(tokens.fillDark, tokens.onFillDark) >= 4.5, "\(id) dark")
            #expect(tokens.fillLight == hex, "\(id) keeps its hue in light mode")
        }
    }

    @Test func unknownIdFallsBackToBlue() {
        #expect(AccentChoice.resolvedHex(choice: "chartreuse", custom: "#112233") == "#2563EB")
        #expect(AccentChoice.resolvedHex(choice: "wine", custom: "#112233") == "#7F1D3F")
        #expect(AccentChoice.resolvedHex(choice: "", custom: "") == "#2563EB")
    }
}

@Suite struct GlowStyleTests {
    @Test func strengthGrowsWithTheLevel() {
        let styles = GlowPreference.allCases.map { GlowStyle(level: $0) }
        #expect(styles.map(\.effectiveLevel) == [0, 1, 2, 3])
        #expect(styles[0].haloOpacity == 0 && styles[0].backdropFactor == 0 && !styles[0].isOn)
        for (a, b) in zip(styles.dropFirst(), styles.dropFirst(2)) {
            #expect(a.haloOpacity < b.haloOpacity && a.haloRadius < b.haloRadius && a.ringOpacity < b.ringOpacity && a.backdropFactor < b.backdropFactor)
        }
        #expect(styles[1].cardEdgeOpacity == 0 && styles[2].cardEdgeOpacity > 0)
        #expect(styles[1].backdropFactor == 1, "subtle keeps the baseline backdrop")
    }

    @Test func accessibilitySettingsSwitchHalosOff() {
        for level in GlowPreference.allCases {
            for (transparency, contrast) in [(true, false), (false, true), (true, true)] {
                let style = GlowStyle(level: level, reduceTransparency: transparency, increasedContrast: contrast)
                #expect(style.effectiveLevel == 0 && style.haloOpacity == 0 && style.ringRadius == 0 && style.cardEdgeOpacity == 0 && style.backdropFactor == 0)
            }
        }
    }

    @Test func storageKeyAndDefault() {
        #expect(AppearanceKeys.glow == "appearance.glow" && Preferences.defaultGlow == "subtle")
    }
}
