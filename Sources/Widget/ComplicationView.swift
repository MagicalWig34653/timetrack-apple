import SwiftUI
import TimetrackCore
import TimetrackDesign
import WidgetKit

/// Everything a complication needs to draw: the shared non-secret snapshot and the moment it is rendered for.
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    var runningSince: Date? { snapshot.isRunning ? snapshot.startedAt : nil }
    var todaySeconds: Int? { snapshot.todaySeconds(at: date) }
    /// Account accent from the snapshot, with the same derivation as in the apps; watch faces are dark, so the dark `ink` is used.
    var accentInk: Color { Color(hex: AccentDerivation.tokens(for: TTTheme(accentHex: snapshot.accentHex).baseHex).inkDark) }
}

/// Complication strings live in their own table so the watch app can include them for the debug gallery without a name clash.
private func loc(_ resource: LocalizedStringResource) -> Text { Text(resource) }

extension SegmentKind {
    var complicationTitle: LocalizedStringResource {
        switch self {
        case .work, .unknown: LocalizedStringResource("kind.work", table: "Complication")
        case .travel: LocalizedStringResource("kind.travel", table: "Complication")
        case .school: LocalizedStringResource("kind.school", table: "Complication")
        }
    }

    var complicationSymbol: String {
        switch self {
        case .work, .unknown: "briefcase.fill"
        case .travel: "car.fill"
        case .school: "graduationcap.fill"
        }
    }
}

/// Live timer that keeps counting without the app running (the system renders it from the start date).
private struct LiveTimer: View {
    let since: Date

    var body: some View {
        Text(timerInterval: since...Date.distantFuture, pauseTime: nil, countsDown: false, showsHours: true)
            .monospacedDigit()
    }
}

private func totalText(_ seconds: Int) -> String { DurationFormat.hoursMinutes(seconds) }

struct ComplicationView: View {
    let entry: ComplicationEntry
    let family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .accessoryCorner: corner
            default: circular
            }
        }
        .widgetURL(URL(string: "timetrack://today"))
    }

    // MARK: Circular

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.runningSince == nil ? "pause.fill" : entry.snapshot.kind.complicationSymbol)
                    .font(.caption2).foregroundStyle(entry.accentInk)
                if let since = entry.runningSince {
                    LiveTimer(since: since).font(.system(size: 13, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                } else {
                    loc(.init("complication.off", table: "Complication")).font(.system(size: 14, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6)
                }
            }
            .padding(2)
        }
    }

    // MARK: Rectangular

    private var rectangular: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.runningSince == nil ? "pause.circle" : entry.snapshot.kind.complicationSymbol)
                .font(.title3).foregroundStyle(entry.accentInk).widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                if let since = entry.runningSince {
                    loc(entry.snapshot.kind.complicationTitle).font(.caption2).foregroundStyle(.secondary)
                    LiveTimer(since: since).font(.system(.title3, design: .rounded).weight(.semibold)).minimumScaleFactor(0.7).lineLimit(1)
                } else {
                    loc(.init("complication.off", table: "Complication")).font(.headline)
                    if let total = entry.todaySeconds {
                        loc(.init("complication.today \(totalText(total))", table: "Complication")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Inline

    @ViewBuilder private var inline: some View {
        if let since = entry.runningSince {
            Label {
                HStack(spacing: 4) { loc(entry.snapshot.kind.complicationTitle); LiveTimer(since: since) }
            } icon: { Image(systemName: entry.snapshot.kind.complicationSymbol) }
        } else if let total = entry.todaySeconds {
            Label { loc(.init("complication.off_today \(totalText(total))", table: "Complication")) } icon: { Image(systemName: "pause.circle") }
        } else {
            Label { loc(.init("complication.off", table: "Complication")) } icon: { Image(systemName: "pause.circle") }
        }
    }

    // MARK: Corner

    private var corner: some View {
        Group {
            if let since = entry.runningSince {
                LiveTimer(since: since).font(.system(.title3, design: .rounded).weight(.semibold)).minimumScaleFactor(0.5).lineLimit(1)
            } else {
                loc(.init("complication.off", table: "Complication")).font(.system(.title3, design: .rounded).weight(.semibold))
            }
        }
        .widgetLabel {
            if entry.runningSince != nil {
                loc(entry.snapshot.kind.complicationTitle)
            } else if let total = entry.todaySeconds {
                loc(.init("complication.today \(totalText(total))", table: "Complication"))
            } else {
                loc(.init("complication.title", table: "Complication"))
            }
        }
    }
}
