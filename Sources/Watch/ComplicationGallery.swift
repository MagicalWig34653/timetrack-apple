#if DEBUG
import SwiftUI
import TimetrackCore
import WidgetKit

/// Debug-only approximation of the complication families (TT_DEV_GALLERY=running|off) so they can be inspected in the watch simulator,
/// which cannot place complications on a face headlessly. Uses the same `ComplicationView` as the widget extension.
struct ComplicationGallery: View {
    private let running = ComplicationEntry(date: .now, snapshot: .init(
        isRunning: true, kind: .travel, startedAt: .now.addingTimeInterval(-3_723), todaySeconds: 7_200,
        day: "", timeZone: "Europe/Berlin", updatedAt: .now))
    private var off: ComplicationEntry {
        let zone = DayCalendar(timeZone: TimeZone(identifier: "Europe/Berlin") ?? .current)
        return ComplicationEntry(date: .now, snapshot: .init(
            isRunning: false, kind: .work, startedAt: nil, todaySeconds: 12_300,
            day: zone.day(for: .now), timeZone: "Europe/Berlin", updatedAt: .now))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach([ProcessInfo.processInfo.environment["TT_DEV_GALLERY"] == "off" ? off : running], id: \.snapshot.isRunning) { entry in
                    HStack(spacing: 8) {
                        ComplicationView(entry: entry, family: .accessoryCircular).frame(width: 52, height: 52)
                        ComplicationView(entry: entry, family: .accessoryCorner).frame(width: 52, height: 52)
                    }
                    ComplicationView(entry: entry, family: .accessoryRectangular)
                        .frame(height: 52).padding(.horizontal, 6)
                        .background(.quaternary, in: .rect(cornerRadius: 10))
                    ComplicationView(entry: entry, family: .accessoryInline).frame(height: 22)
                }
            }
        }
    }
}
#endif
