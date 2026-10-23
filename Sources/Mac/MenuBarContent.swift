import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Menu bar item: clock symbol, plus the running time while a segment is running.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let running = model.today?.running {
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                Text(running.startedAt, style: .timer).monospacedDigit()
            }
        } else {
            Image(systemName: "clock")
        }
    }
}

/// Window-style menu bar panel: live timer, kind choice, start/stop and today's progress.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("mac.lastKind") private var lastKindRaw = SegmentKind.work.rawValue

    private var kind: SegmentKind {
        SegmentKind(rawValue: lastKindRaw).flatMap { SegmentKind.selectable.contains($0) ? $0 : nil } ?? .work
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.m) {
            if let today = model.today {
                timer(today)
                progress(today)
            } else {
                Text("menubar.signed_out").foregroundStyle(TT.textSecondary)
            }
            Divider()
            HStack {
                Button("menubar.open") {
                    openWindow(id: "main")
                    NSApplication.shared.activate()
                }
                Spacer()
                Button("menubar.quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(TT.Space.l)
        .frame(width: 280)
    }

    @ViewBuilder private func timer(_ today: TodayStore) -> some View {
        if let running = today.running {
            VStack(alignment: .leading, spacing: 2) {
                Text("menubar.running_since \(running.startedAt.clockText(in: model.dayCalendar.timeZone))")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                Text(running.startedAt, style: .timer)
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(TT.textPrimary)
            }
            Button { Task { await today.stop() } } label: { Label("command.stop", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.ttDanger).controlSize(.large)
            ContinueNotice(store: today)
        } else {
            Text("today.not_running").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
            Picker("", selection: Binding(get: { kind }, set: { lastKindRaw = $0.rawValue })) {
                ForEach(SegmentKind.selectable, id: \.self) { Label($0.titleKey, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Button { Task { await today.start(kind: kind) } } label: { Label("command.start", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.ttPrimary).controlSize(.large)
            continueActions(today)
            ContinueNotice(store: today)
        }
    }

    /// H5: "Fortführen" in the menu bar panel. No dialog inside the panel: with a long gap both outcomes are shown as buttons.
    @ViewBuilder private func continueActions(_ today: TodayStore) -> some View {
        if let offer = today.continueOffer {
            let until = offer.endedAt.clockText(in: model.dayCalendar.timeZone)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: TT.Space.xs) {
                    if offer.isLongGap(now: context.date) {
                        Button { Task { await today.continueLast() } } label: { Label(ux3String("h4.continue.with_gap"), systemImage: "arrow.uturn.forward").frame(maxWidth: .infinity) }
                            .buttonStyle(.ttSecondary).accessibilityIdentifier("menubar.continue")
                        Button { Task { await today.continueLast(startNew: true) } } label: { Label(ux3String("h4.continue.fresh"), systemImage: "play").frame(maxWidth: .infinity) }
                            .buttonStyle(.ttSecondary).accessibilityIdentifier("menubar.continue.fresh")
                    } else {
                        Button { Task { await today.continueLast() } } label: {
                            Label(ux3String("h4.continue \(offer.kind.plainName) \(until)"), systemImage: "arrow.uturn.forward").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.ttSecondary).accessibilityIdentifier("menubar.continue")
                    }
                }
            }
        }
    }

    @ViewBuilder private func progress(_ today: TodayStore) -> some View {
        if let day = today.day {
            let done = day.evaluatedWorkSeconds + day.creditSeconds
            VStack(alignment: .leading, spacing: TT.Space.xs) {
                ProgressBar(progress: day.targetSeconds > 0 ? Double(done) / Double(day.targetSeconds) : 0)
                Text("menubar.today_total \(DurationFormat.hoursMinutes(done)) \(DurationFormat.hoursMinutes(day.targetSeconds))")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
        }
    }
}
