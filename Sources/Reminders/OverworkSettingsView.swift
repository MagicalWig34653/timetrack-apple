import Observation
import SwiftUI
import TimetrackCore
import TimetrackDesign
import UIKit
import UserNotifications

/// OT1: settings of the overwork notifications. The switches live in the App Group (the intents that pause or resume the timer plan the
/// notifications too); permission is asked only when the first type is switched on (same flow as the vacation reminders, `NotificationPermission`).
@MainActor
@Observable
final class OverworkCenter {
    static let shared = OverworkCenter()

    private(set) var settings: OverworkSettings
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount = 0
    @ObservationIgnored private let store: OverworkSettingsStore

    init(store: OverworkSettingsStore = OverworkSettingsStore()) {
        self.store = store
        settings = store.read()
    }

    var isAuthorized: Bool { NotificationPermission.isGranted(authorization) }

    func refresh() async {
        authorization = await NotificationPermission.status()
        if settings.isAnyEnabled, !isAuthorized { // permission withdrawn in iOS Settings: no switch may claim notifications that cannot arrive
            save(OverworkSettings())
        }
        scheduledCount = await OverworkScheduler.pendingCount()
    }

    func set(_ keyPath: WritableKeyPath<OverworkSettings, Bool>, to on: Bool) async {
        if on {
            authorization = await NotificationPermission.requestIfNeeded()
            guard isAuthorized else { return } // refused: the switch stays off, the page explains
        }
        var copy = settings
        copy[keyPath: keyPath] = on
        save(copy)
        await OverworkScheduler.syncFromStoredSnapshot()
        scheduledCount = await OverworkScheduler.pendingCount()
    }

    private func save(_ value: OverworkSettings) {
        settings = value
        store.write(value)
    }
}

/// Settings > "Überstunden-Hinweise".
struct OverworkSettingsView: View {
    @State private var center = OverworkCenter.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                intro
                if center.authorization == .denied { deniedCard }
                FormSection("Hinweise", footer: "Beim ersten Einschalten fragt iOS einmal nach der Erlaubnis für Mitteilungen. Die Hinweise gelten nur auf diesem Gerät.") {
                    toggle("Geplantes Ende erreicht", "clock.badge.checkmark", \.plannedEnd, id: "overwork.planned_end")
                    toggle("Tagesgrenzen 8 und 10 Stunden", "gauge.with.dots.needle.67percent", \.dailyLimits, id: "overwork.limits")
                    toggle("Pause fehlt", "cup.and.saucer", \.missingBreak, id: "overwork.break")
                }
                if center.settings.isAnyEnabled {
                    FormSection { statusRow }
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("Überstunden-Hinweise")
        .navigationBarTitleDisplayMode(.inline)
        .task { await center.refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await center.refresh() } } }
    }

    private func toggle(_ title: String, _ symbol: String, _ keyPath: WritableKeyPath<OverworkSettings, Bool>, id: String) -> some View {
        Toggle(isOn: Binding(get: { center.settings[keyPath: keyPath] }, set: { value in Task { await center.set(keyPath, to: value) } })) {
            Label(title, systemImage: symbol).foregroundStyle(TT.textPrimary)
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
        .accessibilityIdentifier(id)
    }

    private var intro: some View {
        Card {
            HStack(alignment: .top, spacing: TT.Space.m) {
                KindGlyph(symbol: "bell.badge", tint: TT.kindWork)
                VStack(alignment: .leading, spacing: TT.Space.xs) {
                    Text("Bei langen Tagen informiert").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                    Text("Solange die Zeiterfassung läuft, meldet sich Timetrack zum geplanten Ende, vor und bei den Tagesgrenzen von 8 und 10 Stunden und wenn nach 6 beziehungsweise 9 Stunden die Pause fehlt. Pause, Weiter und Stopp verschieben die Zeitpunkte. Es sind Hinweise, keine Rechtsprüfung; gezählt werden nur tatsächlich erfasste Zeiten.")
                        .font(TTFont.body).foregroundStyle(TT.textSecondary)
                }
            }
        }
    }

    private var deniedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                Label("Mitteilungen sind ausgeschaltet", systemImage: "bell.slash").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                Text("Du hast Mitteilungen für Timetrack abgelehnt. Erlaube sie in den iOS-Einstellungen, damit Hinweise ankommen können.")
                    .font(TTFont.body).foregroundStyle(TT.textSecondary).accessibilityIdentifier("overwork.denied")
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Label("iOS-Einstellungen öffnen", systemImage: "gearshape") }
                    .buttonStyle(.ttSecondary).accessibilityIdentifier("overwork.open_settings")
            }
        }
    }

    private var statusRow: some View {
        HStack {
            Text("Aktuell geplante Hinweise").font(TTFont.body).foregroundStyle(TT.textPrimary)
            Spacer()
            StatusChip(verbatim: "\(center.scheduledCount)", tone: .neutral).accessibilityIdentifier("overwork.count")
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
    }
}
