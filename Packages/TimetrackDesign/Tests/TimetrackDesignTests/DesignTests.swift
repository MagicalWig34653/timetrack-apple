import SwiftUI
import Testing
@testable import TimetrackDesign

@MainActor
@Suite struct DesignTests {
    @Test func hexParsing() {
        #expect(Color(hex: "#2563EB") != nil)
        #expect(Color(hex: "2563eb") != nil)
        #expect(Color(hex: "nope") == nil)
        #expect(Color(hex: "#12345") == nil)
    }

    @Test func themeFallsBackToDefaultOnInvalidHex() {
        #expect(TTTheme(accentHex: "garbage").accent == TTTheme().accent)
        #expect(TTTheme(accentHex: "#FF0000").accent != TTTheme().accent)
    }

    #if os(macOS)
    /// Renders the gallery to PNG files when TT_GALLERY_OUT points to a directory (manual visual check on macOS).
    @Test func rendersGalleryImages() throws {
        guard let out = ProcessInfo.processInfo.environment["TT_GALLERY_OUT"] else { return }
        for (name, scheme, running) in [("light", ColorScheme.light, false), ("dark-running", .dark, true)] {
            let view = DesignGallery(running: running, scrollable: false).environment(\.colorScheme, scheme)
                .frame(width: 640, height: 1500)
                .background(TT.background)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.5
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("render failed")
                continue
            }
            try png.write(to: URL(fileURLWithPath: out).appendingPathComponent("gallery-mac-\(name).png"))
        }
    }
    #endif
}
