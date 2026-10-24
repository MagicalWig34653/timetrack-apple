import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Menu bar item: clock symbol, plus (optionally) the running time while a segment is running.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(MacPrefs.menuBarShowsTimer) private var showsTimer = true

    var body: some View {
        Group {
            if let running = model.today?.running {
                if showsTimer {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                        Text(running.startedAt, style: .timer).monospacedDigit()
                    }
                } else {
                    Image(systemName: "clock.fill")
                }
            } else {
                Image(systemName: "clock")
            }
        }
        .accessibilityLabel(Text(spoken))
        .onAppear { MacCompanion.shared.openMainWindow = { openWindow(id: "main") } }
        .task { await MacBootstrap.run(model) }
    }

    private var spoken: String {
        if let started = model.today?.running?.startedAt { return "Timetrack, Timer läuft seit \(started.formatted(date: .omitted, time: .shortened))" }
        return "Timetrack, kein Timer"
    }
}

/// Start with a kind and remember it for the quick menu (menu bar, toolbar and hotkey share "last kind" and "recent kinds").
@MainActor
func startRecordingKind(_ kind: SegmentKind, in today: TodayStore) async {
    var recent = RecentKinds(rawValues: UserDefaults.standard.string(forKey: MacPrefs.recentKinds) ?? "")
    recent.record(kind)
    UserDefaults.standard.set(recent.rawValues, forKey: MacPrefs.recentKinds)
    UserDefaults.standard.set(kind.rawValue, forKey: "mac.lastKind")
    await today.start(kind: kind)
}

/// Window-style menu bar panel: live timer, today's standing, quick start by recent kinds, continue, window and settings.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(MacPrefs.recentKinds) private var recentRaw = ""
    @State private var companion = MacCompanion.shared

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.m) {
            if let today = model.today {
                timer(today)
                standing(today)
            } else {
                Text("menubar.signed_out").foregroundStyle(TT.textSecondary)
            }
            Divider()
            footer
        }
        .padding(TT.Space.l)
        .frame(width: 300)
    }

    @ViewBuilder private func timer(_ today: TodayStore) -> some View {
        if let running = today.running {
            VStack(alignment: .leading, spacing: 2) {
                Label(running.kind.plainName, systemImage: running.kind.symbol).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                Text(running.startedAt, style: .timer)
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(TT.textPrimary)
                Text("menubar.running_since \(running.startedAt.clockText(in: model.dayCalendar.timeZone))")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
            .accessibilityElement(children: .combine)
            Button { Task { await today.stop() } } label: { Label("command.stop", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.ttDanger).controlSize(.large)
                .accessibilityIdentifier("menubar.stop")
            ContinueNotice(store: today)
        } else {
            Text("today.not_running").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
            quickStart(today)
            continueActions(today)
            ContinueNotice(store: today)
        }
    }

    /// One start button per recent kind (newest first); the first one is the prominent default.
    private func quickStart(_ today: TodayStore) -> some View {
        let kinds = RecentKinds(rawValues: recentRaw).quickStart
        return VStack(spacing: TT.Space.xs) {
            ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                if index == 0 {
                    Button { Task { await startRecordingKind(kind, in: today) } } label: {
                        Label("Starten: \(kind.plainName)", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttPrimary).controlSize(.large)
                    .accessibilityIdentifier("menubar.start.\(kind.rawValue)")
                } else {
                    Button { Task { await startRecordingKind(kind, in: today) } } label: {
                        Label("Starten: \(kind.plainName)", systemImage: kind.symbol).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttSecondary)
                    .accessibilityIdentifier("menubar.start.\(kind.rawValue)")
                }
            }
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

    /// Soll / Ist as a bar plus the calm outlook lines (Feierabend, Pause) from the shared H3 logic.
    @ViewBuilder private func standing(_ today: TodayStore) -> some View {
        if let day = today.day {
            let done = day.evaluatedWorkSeconds + day.creditSeconds
            VStack(alignment: .leading, spacing: TT.Space.xs) {
                ProgressBar(progress: day.targetSeconds > 0 ? Double(done) / Double(day.targetSeconds) : 0)
                Text("menubar.today_total \(DurationFormat.hoursMinutes(done)) \(DurationFormat.hoursMinutes(day.targetSeconds))")
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    DayOutlookLines(outlook: today.outlook(now: context.date), zone: model.dayCalendar.timeZone)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: TT.Space.xs) {
            if companion.activity.settings.enabled {
                Toggle(isOn: Binding(get: { companion.activity.settings.paused }, set: { value in companion.activity.update { $0.paused = value } })) {
                    Label("Aktivitätserfassung pausieren", systemImage: "pause.circle")
                }
                .toggleStyle(.switch).controlSize(.small)
                .accessibilityIdentifier("menubar.pauseActivity")
            }
            Button {
                companion.showMainWindow()
                openWindow(id: "main")
            } label: { Label("menubar.open", systemImage: "macwindow") }
                .keyboardShortcut("o")
            HStack {
                Button { NSApp.setActivationPolicy(.regular); NSApp.activate(); openSettings() } label: { Label("Einstellungen…", systemImage: "gearshape") }
                    .keyboardShortcut(",")
                Spacer()
                Button { companion.quit(); NSApplication.shared.terminate(nil) } label: { Label("Beenden", systemImage: "power") }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
    }
}
