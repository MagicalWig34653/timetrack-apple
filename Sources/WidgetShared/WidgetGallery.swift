#if DEBUG && os(iOS)
import SwiftUI
import TimetrackCore
import TimetrackDesign
import WidgetKit

/// Debug-only: draws the widget views inside the app because widgets cannot be placed on a simulator Home Screen headlessly.
/// `TT_DEV_WIDGET_GALLERY=running|idle|signedout|stale`; approximates the system container (rounded background, 16 pt margins),
/// but not Lock Screen vibrancy, tinting, Dynamic Island or Control Center.
struct WidgetGallery: View {
    static var rawMode: String? { ProcessInfo.processInfo.environment["TT_DEV_WIDGET_GALLERY"] }
    /// A "-live" suffix shows only the Live Activity part (e.g. `running-live`).
    static var mode: String? { rawMode?.replacingOccurrences(of: "-live", with: "") }
    static var liveOnly: Bool { rawMode?.hasSuffix("-live") ?? false }
    static var isRequested: Bool { rawMode != nil }
    /// LA1 sample switches: `TT_DEV_LA_PAUSED=1`, `TT_DEV_LA_NOPLAN=1`, `TT_DEV_LA_ACCENT=#RRGGBB`.
    static var pausedSample: Bool { ProcessInfo.processInfo.environment["TT_DEV_LA_PAUSED"] == "1" }
    static var noPlanSample: Bool { ProcessInfo.processInfo.environment["TT_DEV_LA_NOPLAN"] == "1" }
    static var accentSample: String? { ProcessInfo.processInfo.environment["TT_DEV_LA_ACCENT"] }

    @Environment(\.colorScheme) private var scheme

    private var entry: TimetrackEntry {
        switch Self.mode {
        case "idle": .sample(running: false)
        case "signedout": TimetrackEntry(date: .now, snapshot: nil)
        case "stale":
            { var sample = TimetrackEntry.sample(running: false); let old = sample.date.addingTimeInterval(-3 * 3600)
              sample = TimetrackEntry(date: sample.date, snapshot: sample.snapshot.map { var copy = $0; copy.updatedAt = old; return copy }); return sample }()
        default: .sample(running: true, kind: .travel)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: "Widget gallery: \(Self.mode ?? "")").font(.headline).foregroundStyle(TT.textPrimary)
                if !Self.liveOnly {
                    HStack(alignment: .top, spacing: 16) {
                        tile(.systemSmall, width: 158, height: 158)
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                accessory(.accessoryCircular, width: 72, height: 72)
                                accessory(.accessoryInline, width: 100, height: 24)
                            }
                            accessory(.accessoryRectangular, width: 172, height: 76)
                        }
                    }
                    tile(.systemMedium, width: 338, height: 158)
                    tile(.systemLarge, width: 338, height: 354)
                }
                Text(verbatim: "Live Activity / Dynamic Island").font(.subheadline.bold()).foregroundStyle(TT.textSecondary)
                #if os(iOS)
                LiveActivityPreview(state: .sample(paused: Self.pausedSample, kind: entry.kind, planned: !Self.noPlanSample, accentHex: Self.accentSample))
                #endif
            }
            .padding(16)
        }
        .background(TT.background)
        .environment(\.colorScheme, scheme)
    }

    private func tile(_ family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            TT.background
            TimetrackWidgetView(entry: entry, family: family).padding(16)
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(TT.cardBorder) }
    }

    private func accessory(_ family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
        TimetrackWidgetView(entry: entry, family: family)
            .frame(width: width, height: height)
            .background(Color.black, in: .rect(cornerRadius: 16))
            .environment(\.colorScheme, .dark)
    }
}
#endif
