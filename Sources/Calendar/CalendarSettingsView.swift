import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores
#if canImport(UIKit)
import UIKit
#endif

/// Settings > "Kalender": permission flow and, per calendar, off / read / read+write. Read shows events as context in the day view;
/// read+write additionally writes planned vacation and sick days (optionally plan days) as all-day events. Everything stays on this device.
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: scenePhase) { if scenePhase == .active { store?.refresh() } } // the user may have changed the permission in iOS Settings
        .task { store?.refresh() }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { openURL(url) }
        #endif
    }
}

private struct CalendarSettingsContent: View {
    let store: DeviceCalendarStore
    let openSettings: () -> Void
    @State private var confirmRemoval = false

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
                    Text("Du legst für jeden Kalender fest, was Timetrack damit tut: nichts, nur lesen oder lesen und schreiben („Schreiben“ schließt Lesen ein). Gelesene Termine erscheinen im Tag der Kalenderansicht, nur zur Ansicht. In Kalender mit „Schreiben“ trägt Timetrack deinen geplanten Urlaub und Krankheitstage ein.")
                        .font(TTFont.body).foregroundStyle(TT.textSecondary)
                }
            }
        }
    }

    // MARK: Permission

    private var accessSection: some View {
        FormSection("Zugriff", footer: "iOS vergibt das Lesen von Terminen nur zusammen mit dem Schreiben („Vollzugriff“). Timetrack liest nur Kalender auf „Lesen“ oder „Schreiben“ und schreibt nur in Kalender auf „Schreiben“.") {
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
                            footer: group.key == groups.first?.key ? "Standard ist „Aus“: Ohne Auswahl liest und schreibt Timetrack nichts." : nil) {
                    ForEach(group.value) { calendar in modeRow(calendar) }
                }
            }
            FormSection {
                Toggle("Ganztägige Termine anzeigen", isOn: Binding(get: { store.preferences.showAllDay }, set: { store.setShowAllDay($0) }))
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s).accessibilityIdentifier("calendar.allday")
            }
        }
    }

    private func modeRow(_ calendar: DeviceCalendarInfo) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            HStack(spacing: TT.Space.m) {
                Circle().fill(color(calendar)).frame(width: 12, height: 12).accessibilityHidden(true)
                Text(verbatim: calendar.title).font(TTFont.body).foregroundStyle(TT.textPrimary)
                if !calendar.allowsWrite {
                    Text("nur Lesen möglich").font(TTFont.meta).foregroundStyle(TT.textTertiary)
                }
            }
            Picker(selection: Binding(get: { store.mode(for: calendar.id) }, set: { mode in Task { await store.setMode(mode, for: calendar.id) } })) {
                Text("Aus").tag(CalendarMode.off)
                Text("Lesen").tag(CalendarMode.read)
                if calendar.allowsWrite { Text("Schreiben").tag(CalendarMode.readWrite) }
            } label: {
                Text(verbatim: "Modus für \(calendar.title)")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("calendar.mode.\(calendar.title)")
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
        .accessibilityElement(children: .contain)
    }

    private func color(_ calendar: DeviceCalendarInfo) -> Color {
        calendar.colorHex.flatMap { UInt32($0, radix: 16) }.map { Color(hex: $0) } ?? TT.textTertiary
    }

    // MARK: Writing

    private var writeSection: some View {
        VStack(alignment: .leading, spacing: TT.Space.xl) {
            FormSection("Was geschrieben wird",
                        footer: "Gilt für alle Kalender auf „Schreiben“. Titel sind allgemein („Urlaub (geplant)“, „Krank“); Notizen, Orte und Krankschein-Stand stehen nie im Kalender. Geplante Arbeitsblöcke eines Tages erscheinen als einzelne Termine mit Uhrzeit, Tage ohne Uhrzeiten als ganztägiger Termin. Timetrack ändert oder löscht nur Termine mit eigener Kennung, nie andere. Stellst du einen Kalender zurück auf „Lesen“ oder „Aus“, entfernt Timetrack die dort geschriebenen Termine.") {
                Toggle("Geplanten Urlaub und Krank schreiben", isOn: Binding(get: { store.preferences.writeAbsences }, set: { store.setWriteAbsences($0) }))
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s).accessibilityIdentifier("calendar.write.absences")
                Toggle("Geplante Arbeitstage schreiben", isOn: Binding(get: { store.preferences.writePlanDays }, set: { store.setWritePlanDays($0) }))
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s).accessibilityIdentifier("calendar.write.plan")
                if store.preferences.writeCalendarIDs.isEmpty {
                    Text("Noch kein Kalender steht auf „Schreiben“, es wird nichts geschrieben.").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        .padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.m).accessibilityIdentifier("calendar.write.none")
                } else {
                    let result = store.lastWrite ?? .skipped
                    Text(verbatim: summary(result)).font(TTFont.meta).foregroundStyle(result == .failed ? TT.danger : TT.textSecondary)
                        .padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.m).accessibilityIdentifier("calendar.write.result")
                }
            }
            FormSection("Aufräumen") {
                VStack(alignment: .leading, spacing: TT.Space.m) {
                    if !store.hasTimetrackCalendar {
                        Button { Task { await store.createTimetrackCalendar() } } label: { Label("Eigenen Kalender „Timetrack“ anlegen", systemImage: "calendar.badge.plus") }
                            .buttonStyle(.ttSecondary).accessibilityIdentifier("calendar.create")
                    }
                    Button(role: .destructive) { confirmRemoval = true } label: { Label { Text("Von Timetrack geschriebene Termine entfernen").fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "trash") } }
                        .buttonStyle(.ttSecondary).accessibilityIdentifier("calendar.remove")
                    if let removed = store.lastRemoval {
                        Text(verbatim: removed == 0 ? "Es gab keine Termine von Timetrack." : "\(removed) Termine von Timetrack entfernt.")
                            .font(TTFont.meta).foregroundStyle(TT.textSecondary).accessibilityIdentifier("calendar.remove.result")
                    }
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            }
        }
        .confirmationDialog("Alle von Timetrack geschriebenen Termine entfernen?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Termine entfernen", role: .destructive) { store.removeAllWritten(calendar: DayCalendar(timeZone: .current)) }
                .accessibilityIdentifier("calendar.remove.confirm")
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Es werden nur Termine gelöscht, die Timetrack selbst geschrieben hat. Deine eigenen Termine bleiben unberührt.")
        }
    }

    private func summary(_ result: CalendarWriteResult) -> String {
        switch result {
        case .written(let created, let updated, let deleted): "Zuletzt: \(created) neu, \(updated) geändert, \(deleted) entfernt."
        case .skipped: "Noch nichts geschrieben. Die Termine werden beim Öffnen der Kalenderansicht übertragen."
        case .failed: "Das Schreiben ist fehlgeschlagen."
        }
    }
}
