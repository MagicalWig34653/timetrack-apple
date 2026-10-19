import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
import UIKit

/// Settings > "Kalender": permission flow, choice of calendars (read-only context in the day view) and the optional write-back of
/// planned work days into a dedicated "Timetrack" calendar. Everything here stays on this device.
struct CalendarSettingsView: View {
    @Environment(\.deviceCalendar) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                if let store {
                    CalendarSettingsContent(store: store, openSettings: openSystemSettings)
                } else {
                    EmptyState(symbol: "calendar.badge.exclamationmark", title: "Kalender nicht verfügbar")
                }
            }
            .padding(.horizontal, TT.Space.l)
            .padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle("Kalender")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { if scenePhase == .active { store?.refresh() } } // the user may have changed the permission in iOS Settings
        .task { store?.refresh() }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

private struct CalendarSettingsContent: View {
    let store: DeviceCalendarStore
    let openSettings: () -> Void

    var body: some View {
        introCard
        accessSection
        if store.access.canRead {
            calendarsSection
            writeSection
        }
        Text("Titel, Orte und Teilnehmer deiner Termine verlassen dieses Gerät nie und werden nicht an den Timetrack-Server gesendet. Termine werden nie automatisch zu Zeiteinträgen.")
            .font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.s)
            .accessibilityIdentifier("calendar.privacy")
    }

    private var introCard: some View {
        Card {
            HStack(alignment: .top, spacing: TT.Space.m) {
                KindGlyph(symbol: "calendar", tint: TT.kindHoliday)
                VStack(alignment: .leading, spacing: TT.Space.xs) {
                    Text("Termine als Kontext").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                    Text("Timetrack zeigt Termine ausgewählter Kalender im Tag der Kalenderansicht, nur zur Ansicht. Auf Wunsch schlägst du aus einem Termin einen Zeitabschnitt vor, den du selbst einordnest und bestätigst.")
                        .font(TTFont.body).foregroundStyle(TT.textSecondary)
                }
            }
        }
    }

    // MARK: Permission

    private var accessSection: some View {
        FormSection("Zugriff", footer: "iOS vergibt das Lesen von Terminen nur zusammen mit dem Schreiben („Vollzugriff“). Timetrack liest nur die Kalender, die du unten auswählst, und schreibt nur, wenn du das Schreiben selbst einschaltest.") {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                HStack {
                    Text("Kalenderzugriff").font(TTFont.body).foregroundStyle(TT.textPrimary)
                    Spacer()
                    StatusChip(statusTitle, tone: statusTone, symbol: statusSymbol).accessibilityIdentifier("calendar.access.status")
                }
                switch store.access {
                case .notDetermined:
                    Button { Task { await store.requestAccess() } } label: { Label("Zugriff erlauben", systemImage: "calendar.badge.plus") }
                        .buttonStyle(.ttSecondary).disabled(store.isRequesting).accessibilityIdentifier("calendar.allow")
                case .denied, .restricted, .writeOnly:
                    Text(store.access == .writeOnly ? "Es besteht nur Schreibzugriff. Zum Anzeigen von Terminen ist „Voller Zugriff“ nötig." : "Der Zugriff ist ausgeschaltet. Du kannst ihn in den iOS-Einstellungen ändern.")
                        .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    if store.access != .restricted {
                        Button { openSettings() } label: { Label("iOS-Einstellungen öffnen", systemImage: "gearshape") }
                            .buttonStyle(.ttSecondary).accessibilityIdentifier("calendar.open_settings")
                    }
                case .full:
                    EmptyView()
                }
                if let message = store.message {
                    Text(verbatim: message).font(TTFont.meta).foregroundStyle(TT.danger).accessibilityIdentifier("calendar.message")
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        }
    }

    private var statusTitle: LocalizedStringKey {
        switch store.access {
        case .full: "Erlaubt"
        case .writeOnly: "Nur Schreiben"
        case .denied: "Abgelehnt"
        case .restricted: "Eingeschränkt"
        case .notDetermined: "Nicht angefragt"
        }
    }

    private var statusTone: TTTone { store.access == .full ? .success : .neutral }

    private var statusSymbol: String {
        switch store.access {
        case .full: "checkmark.circle"
        case .notDetermined: "questionmark.circle"
        default: "exclamationmark.circle"
        }
    }

    // MARK: Calendars

    private var calendarsSection: some View {
        let groups = Dictionary(grouping: store.selectableCalendars, by: \.accountTitle).sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: TT.Space.xl) {
            if groups.isEmpty {
                FormSection("Kalender", footer: "Auf diesem Gerät sind keine Kalender vorhanden.") { EmptyView() }
            }
            ForEach(groups, id: \.key) { group in
                FormSection(LocalizedStringKey(group.key.isEmpty ? "Kalender" : group.key),
                            footer: group.key == groups.first?.key ? "Ohne Auswahl werden keine Termine angezeigt." : nil) {
                    ForEach(group.value) { calendar in
                        Toggle(isOn: Binding(get: { store.isSelected(calendar.id) }, set: { store.setSelected(calendar.id, $0) })) {
                            HStack(spacing: TT.Space.m) {
                                Circle().fill(color(calendar)).frame(width: 12, height: 12).accessibilityHidden(true)
                                Text(verbatim: calendar.title).font(TTFont.body).foregroundStyle(TT.textPrimary)
                            }
                        }
                        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
                        .accessibilityIdentifier("calendar.select.\(calendar.title)")
                    }
                }
            }
            FormSection {
                Toggle("Ganztägige Termine anzeigen", isOn: Binding(get: { store.preferences.showAllDay }, set: { store.setShowAllDay($0) }))
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s).accessibilityIdentifier("calendar.allday")
            }
        }
    }

    private func color(_ calendar: DeviceCalendarInfo) -> Color {
        calendar.colorHex.flatMap { UInt32($0, radix: 16) }.map { Color(hex: $0) } ?? TT.textTertiary
    }

    // MARK: Write-back

    private var writeSection: some View {
        FormSection("Schreiben (optional)",
                    footer: "Ist das Schreiben an, legt Timetrack einen eigenen Kalender „Timetrack“ an und trägt dort deine geplanten Arbeitstage (Büro, Homeoffice, Kunde, Schule) als ganztägige Termine ein. Uhrzeiten gibt es im Plan nicht, deshalb werden keine erfunden. Deine anderen Kalender werden nie verändert.") {
            Toggle("Geplante Arbeitstage in Kalender „Timetrack“ schreiben", isOn: Binding(get: { store.preferences.writeEnabled }, set: { value in Task { await store.setWriteEnabled(value) } }))
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m).accessibilityIdentifier("calendar.write")
            if store.preferences.writeEnabled {
                let result = store.lastWrite ?? .skipped
                Text(verbatim: summary(result)).font(TTFont.meta).foregroundStyle(result == .failed ? TT.danger : TT.textSecondary)
                    .padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.m).accessibilityIdentifier("calendar.write.result")
            }
        }
    }

    private func summary(_ result: CalendarWriteResult) -> String {
        switch result {
        case .written(let created, let updated, let deleted): "Zuletzt: \(created) neu, \(updated) geändert, \(deleted) entfernt."
        case .skipped: "Noch nichts geschrieben. Der Plan wird beim Öffnen der Kalenderansicht übertragen."
        case .failed: "Das Schreiben ist fehlgeschlagen."
        }
    }
}
