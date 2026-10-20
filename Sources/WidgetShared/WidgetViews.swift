import SwiftUI
import TimetrackCore
import TimetrackDesign
import WidgetKit
#if os(iOS)
import AppIntents
#endif

/// Entry point used by the widget extensions and the in-app debug gallery.
struct TimetrackWidgetView: View {
    let entry: TimetrackEntry
    let family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallWidget(entry: entry)
            case .systemMedium: MediumWidget(entry: entry)
            case .systemLarge, .systemExtraLarge: LargeWidget(entry: entry)
            #if os(iOS)
            case .accessoryCircular: AccessoryCircular(entry: entry)
            case .accessoryRectangular: AccessoryRectangular(entry: entry)
            case .accessoryInline: AccessoryInline(entry: entry)
            #endif
            default: SmallWidget(entry: entry)
            }
        }
        .widgetURL(WidgetLinks.today)
    }
}

// MARK: - Shared pieces

/// Start/stop pill. Interactive on iOS (the intent runs without opening the app); on macOS the widget is display only.
private struct TimerActionButton: View {
    let running: Bool
    /// Account accent from the snapshot; the start pill uses its fill and the matching on-accent text colour (>= 4.5:1).
    let theme: TTTheme
    var compact = false

    var body: some View {
        #if os(iOS)
        Group {
            if running {
                Button(intent: WidgetStopTimerIntent()) { label }
            } else {
                Button(intent: WidgetStartTimerIntent()) { label }
            }
        }
        .buttonStyle(.plain)
        #else
        EmptyView()
        #endif
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: running ? "stop.fill" : "play.fill").imageScale(.small)
            if !compact { (running ? wtext("w.stop") : wtext("w.start")).lineLimit(1) }
        }
        .font(.system(.footnote, design: .rounded, weight: .semibold))
        .foregroundStyle(running ? Color.white : theme.onAccent)
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, 7)
        .frame(minWidth: compact ? 34 : nil)
        .background(running ? TT.dangerFill : theme.accent, in: .capsule)
    }
}

private struct KindLabel: View {
    let kind: SegmentKind
    var live = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.ttSymbol).imageScale(.small)
            kind.widgetTitle
            if live { Circle().fill(kind.ttTint).frame(width: 6, height: 6) }
        }
        .font(.system(.footnote, weight: .semibold))
        .foregroundStyle(kind.ttTint)
        .lineLimit(1)
    }
}

private struct StaleNote: View {
    let entry: TimetrackEntry

    var body: some View {
        if entry.isStale, let updated = entry.snapshot?.updatedAt {
            wtext("w.updated \(updated.widgetClock(in: entry.zone))")
                .font(.caption2).foregroundStyle(TT.textTertiary).lineLimit(1)
        }
    }
}

private struct SignedOutWidget: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark").font(.title2).foregroundStyle(TT.textSecondary)
            wtext("w.signin").font(.system(.footnote, weight: .medium)).foregroundStyle(TT.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func hoursMinutes(_ seconds: Int) -> String { DurationFormat.hoursMinutes(seconds) }

/// Time worked today as h:mm (UX3: the "Dauern immer h:mm" rule; a second ticking number next to the live timer was noise).
/// While a timer runs, the provider hands out one entry per minute, so the figure moves on without ticking seconds.
private struct TodayTotalText: View {
    let entry: TimetrackEntry

    var body: some View {
        if let total = entry.todaySeconds {
            Text(verbatim: hoursMinutes(total + runningSeconds))
        } else if let since = entry.runningSince {
            Text(verbatim: hoursMinutes(Int(max(0, entry.date.timeIntervalSince(since)))))
        } else {
            Text(verbatim: "–")
        }
    }

    /// Seconds of the running segment at the moment this entry is rendered for.
    private var runningSeconds: Int {
        guard let since = entry.runningSince else { return 0 }
        return Int(max(0, entry.date.timeIntervalSince(since)))
    }
}

private struct StatRow<Value: View>: View {
    let title: LocalizedStringResource
    let value: Value
    var tint: Color = TT.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.caption, weight: .medium)).foregroundStyle(TT.textSecondary).lineLimit(1)
            Spacer(minLength: 4)
            value.font(.system(.callout, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

private struct DayRing: View {
    let entry: TimetrackEntry
    var lineWidth: CGFloat = 9

    var body: some View {
        ProgressRing(progress: entry.progress ?? 0, lineWidth: lineWidth, tint: entry.progress.map { $0 >= 1 ? TT.success : entry.theme.accent } ?? TT.textTertiary) {
            VStack(spacing: 0) {
                TodayTotalText(entry: entry)
                    .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                if let target = entry.targetSeconds, target > 0 {
                    wtext("w.of_target \(hoursMinutes(target))").font(.system(.caption2, weight: .medium)).foregroundStyle(TT.textSecondary).lineLimit(1)
                } else {
                    wtext("w.today").font(.system(.caption2, weight: .medium)).foregroundStyle(TT.textSecondary)
                }
            }
            .padding(lineWidth + 2)
        }
    }
}

private extension View {
    func widgetBackground() -> some View { containerBackground(for: .widget) { TT.background } }
}

// MARK: - Small

struct SmallWidget: View {
    let entry: TimetrackEntry

    var body: some View {
        Group {
            if entry.snapshot == nil {
                SignedOutWidget()
            } else if let since = entry.runningSince {
                VStack(alignment: .leading, spacing: 4) {
                    KindLabel(kind: entry.kind, live: true)
                    Spacer(minLength: 0)
                    LiveTimerText(since: since)
                        .font(.system(size: 34, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                        .foregroundStyle(TT.textPrimary)
                    wtext("w.since \(since.widgetClock(in: entry.zone))").font(.system(.caption, weight: .medium)).foregroundStyle(TT.textSecondary)
                    Spacer(minLength: 2)
                    HStack { TimerActionButton(running: true, theme: entry.theme); Spacer(minLength: 0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 4) {
                    HStack(alignment: .top) {
                        wtext("w.idle").font(.system(.footnote, weight: .semibold)).foregroundStyle(TT.textSecondary)
                        Spacer(minLength: 0)
                        TimerActionButton(running: false, theme: entry.theme, compact: true)
                    }
                    DayRing(entry: entry, lineWidth: 8)
                    StaleNote(entry: entry)
                }
            }
        }
        .widgetBackground()
    }
}

// MARK: - Medium

private struct StatsColumn: View {
    let entry: TimetrackEntry

    var body: some View {
        VStack(spacing: 7) {
            StatRow(title: LocalizedStringResource("w.captured", table: "Widget"), value: TodayTotalText(entry: entry))
            Divider().overlay(TT.separator)
            StatRow(title: LocalizedStringResource("w.target", table: "Widget"),
                    value: Text(verbatim: entry.targetSeconds.map(hoursMinutes) ?? "–"))
            Divider().overlay(TT.separator)
            StatRow(title: LocalizedStringResource("w.balance", table: "Widget"),
                    value: Text(verbatim: entry.balanceSeconds.map(DurationFormat.signed) ?? "–"),
                    tint: (entry.balanceSeconds ?? 0) < 0 ? TT.danger : TT.textPrimary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(TT.surface, in: .rect(cornerRadius: TT.Radius.control))
        .overlay { RoundedRectangle(cornerRadius: TT.Radius.control).strokeBorder(TT.cardBorder) }
    }
}

struct MediumContent: View {
    let entry: TimetrackEntry

    var body: some View {
        if entry.snapshot == nil {
            SignedOutWidget()
        } else {
            HStack(spacing: 14) {
                Group {
                    if let since = entry.runningSince {
                        VStack(alignment: .leading, spacing: 4) {
                            KindLabel(kind: entry.kind, live: true)
                            Spacer(minLength: 0)
                            LiveTimerText(since: since)
                                .font(.system(size: 32, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                            wtext("w.since \(since.widgetClock(in: entry.zone))").font(.system(.caption, weight: .medium)).foregroundStyle(TT.textSecondary)
                            Spacer(minLength: 2)
                            HStack { TimerActionButton(running: true, theme: entry.theme); Spacer(minLength: 0) }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            wtext("w.idle").font(.system(.footnote, weight: .semibold)).foregroundStyle(TT.textSecondary)
                            DayRing(entry: entry, lineWidth: 7).frame(maxWidth: .infinity, maxHeight: 76)
                            Spacer(minLength: 2)
                            HStack { TimerActionButton(running: false, theme: entry.theme); Spacer(minLength: 0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 4) {
                    StatsColumn(entry: entry)
                    StaleNote(entry: entry)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct MediumWidget: View {
    let entry: TimetrackEntry
    var body: some View { MediumContent(entry: entry).widgetBackground() }
}

// MARK: - Large

private struct SegmentLine: View {
    let segment: WidgetSegment
    let zone: TimeZone

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: segment.kind.ttSymbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(segment.kind.ttTint)
                .frame(width: 22, height: 22).background(segment.kind.ttTint.opacity(0.14), in: .rect(cornerRadius: 7))
            segment.kind.widgetTitle.font(.system(.footnote, weight: .medium)).foregroundStyle(TT.textPrimary)
            Spacer(minLength: 4)
            if let end = segment.endedAt {
                Text(verbatim: "\(segment.startedAt.widgetClock(in: zone)) – \(end.widgetClock(in: zone))")
                    .font(.system(.caption)).monospacedDigit().foregroundStyle(TT.textSecondary)
                Text(verbatim: hoursMinutes(Int(end.timeIntervalSince(segment.startedAt))))
                    .font(.system(.footnote, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(TT.textPrimary)
                    .frame(minWidth: 38, alignment: .trailing)
            } else {
                Text(verbatim: "\(segment.startedAt.widgetClock(in: zone)) –").font(.system(.caption)).monospacedDigit().foregroundStyle(TT.textSecondary)
                wtext("w.running").font(.system(.footnote, weight: .semibold)).foregroundStyle(segment.kind.ttTint)
                    .frame(minWidth: 38, alignment: .trailing)
            }
        }
    }
}

struct LargeWidget: View {
    let entry: TimetrackEntry

    var body: some View {
        Group {
            if entry.snapshot == nil {
                SignedOutWidget()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    MediumContent(entry: entry).frame(height: 128)
                    HStack {
                        wtext("w.segments").font(.system(.footnote, weight: .semibold)).foregroundStyle(TT.textSecondary)
                        Spacer()
                        StaleNote(entry: entry)
                    }
                    VStack(spacing: 7) {
                        if entry.segments.isEmpty {
                            wtext("w.no_segments").font(.footnote).foregroundStyle(TT.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(Array(entry.segments.suffix(5).enumerated()), id: \.offset) { _, segment in
                                SegmentLine(segment: segment, zone: entry.zone)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetBackground()
    }
}

// MARK: - Lock screen
#if os(iOS)

private struct AccessoryCircular: View {
    let entry: TimetrackEntry

    var body: some View {
        Group {
            if let since = entry.runningSince {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: entry.kind.ttSymbol).font(.caption2)
                        LiveTimerText(since: since)
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    }
                    .padding(2)
                }
            } else if let progress = entry.progress, let total = entry.todaySeconds {
                Gauge(value: min(progress, 1)) {
                    wtext("w.today")
                } currentValueLabel: {
                    Text(verbatim: hoursMinutes(total)).font(.system(size: 13, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "pause.fill").font(.caption2)
                        wtext("w.idle").font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

private struct AccessoryRectangular: View {
    let entry: TimetrackEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.runningSince == nil ? "pause.circle" : entry.kind.ttSymbol).font(.title3).widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                if let since = entry.runningSince {
                    entry.kind.widgetTitle.font(.caption2).foregroundStyle(.secondary)
                    LiveTimerText(since: since).font(.system(.title3, design: .rounded).weight(.semibold)).minimumScaleFactor(0.7).lineLimit(1)
                    if let total = entry.todaySeconds {
                        wtext("w.today_value \(hoursMinutes(total))").font(.caption2).foregroundStyle(.secondary)
                    }
                } else if entry.snapshot == nil {
                    wtext("w.signin").font(.caption)
                } else {
                    wtext("w.idle").font(.headline)
                    if let total = entry.todaySeconds {
                        wtext("w.today_value \(hoursMinutes(total))").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let progress = entry.progress { ProgressView(value: min(progress, 1)).progressViewStyle(.linear) }
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.clear, for: .widget)
    }
}

private struct AccessoryInline: View {
    let entry: TimetrackEntry

    var body: some View {
        Group {
            if let since = entry.runningSince {
                Label { HStack(spacing: 4) { entry.kind.widgetTitle; LiveTimerText(since: since) } } icon: { Image(systemName: entry.kind.ttSymbol) }
            } else if let total = entry.todaySeconds {
                Label { wtext("w.idle_today \(hoursMinutes(total))") } icon: { Image(systemName: "pause.circle") }
            } else {
                Label { wtext("w.idle") } icon: { Image(systemName: "pause.circle") }
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}
#endif
