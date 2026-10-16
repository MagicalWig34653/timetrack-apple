import SwiftUI
import TimetrackCore
import TimetrackDesign
import WidgetKit

/// Widget strings live in their own table (`Widget.xcstrings`) so the app can include the views for the debug gallery
/// without clashing with its own catalog.
func wtext(_ key: String.LocalizationValue) -> Text { Text(LocalizedStringResource(key, table: "Widget")) }

/// What every Timetrack widget draws: the shared non-secret snapshot (nil = nothing written yet, e.g. signed out) and the moment it is rendered for.
struct TimetrackEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    var runningSince: Date? { snapshot.flatMap { $0.isRunning ? $0.startedAt : nil } }
    var kind: SegmentKind { snapshot?.kind ?? .work }
    /// Finished seconds of today (without the running segment); nil when the snapshot belongs to an earlier day.
    var todaySeconds: Int? { snapshot?.todaySeconds(at: date) }
    var targetSeconds: Int? { todaySeconds == nil ? nil : snapshot?.targetSeconds }
    var balanceSeconds: Int? { snapshot?.balanceSeconds }
    var segments: [WidgetSegment] { snapshot?.segments(at: date) ?? [] }
    var zone: TimeZone { snapshot.flatMap { TimeZone(identifier: $0.timeZone) } ?? .current }
    /// The account accent written by the app (default blue when absent); derivation as in the app.
    var theme: TTTheme { TTTheme(accentHex: snapshot?.accentHex) }
    var isStale: Bool { snapshot?.isStale(at: date) ?? false }

    /// 0...1 progress of the finished time against the target; nil without a target.
    var progress: Double? {
        guard let total = todaySeconds, let target = targetSeconds, target > 0 else { return nil }
        return Double(total) / Double(target)
    }

    static func sample(running: Bool, kind: SegmentKind = .work, now: Date = .now) -> TimetrackEntry {
        let start = now.addingTimeInterval(-3_723)
        let earlier = now.addingTimeInterval(-3 * 3600)
        let segments = [
            WidgetSegment(kind: .school, startedAt: earlier.addingTimeInterval(-2 * 3600), endedAt: earlier.addingTimeInterval(-3_600)),
            WidgetSegment(kind: .travel, startedAt: earlier.addingTimeInterval(-3_000), endedAt: earlier),
            WidgetSegment(kind: .work, startedAt: running ? start : earlier.addingTimeInterval(600), endedAt: running ? nil : earlier.addingTimeInterval(4_000)),
        ]
        let zone = TimeZone.current
        return TimetrackEntry(date: now, snapshot: WidgetSnapshot(
            isRunning: running, kind: kind, startedAt: running ? start : nil, todaySeconds: 12_300,
            day: DayCalendar(timeZone: zone).day(for: now), timeZone: zone.identifier, updatedAt: now,
            targetSeconds: 28_800, balanceSeconds: 5_400, segments: segments
        ))
    }
}

extension SegmentKind {
    var widgetTitle: Text {
        switch self {
        case .work, .unknown: wtext("w.kind.work")
        case .travel: wtext("w.kind.travel")
        case .school: wtext("w.kind.school")
        }
    }
}

enum WidgetLinks {
    /// The widgets only open the app; there is no deeper navigation target.
    static let today = URL(string: "timetrack://today")
}

extension Date {
    /// "08:12" in the work model's zone (the user's local day, not the device's, if they differ).
    func widgetClock(in zone: TimeZone) -> String { formatted(Date.FormatStyle(timeZone: zone).hour().minute()) }
}

/// Live timer that keeps counting without the app running (the system renders it from the start date).
struct LiveTimerText: View {
    let since: Date

    var body: some View {
        Text(timerInterval: since...Date.distantFuture, pauseTime: nil, countsDown: false, showsHours: true)
            .monospacedDigit()
            .contentTransition(.identity)
    }
}
