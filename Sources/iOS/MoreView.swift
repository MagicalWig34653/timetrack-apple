import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// UX3: "Mehr" replaces the "Einstellungen" tab as the place for everything that is not part of the daily path: areas the app does not
/// have natively yet (they open the web app), reminders, automation and the settings themselves. The S2 settings pages stay as they are.
struct MoreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                AccountCard()
                webAreas
                remindersGroup
                automationGroup
                FormSection("App") {
                    SettingsLinkRow(title: "Einstellungen", symbol: "gearshape", id: "more.settings") { SettingsView() }
                }
            }
            .settingsPageLayout()
        }
        .ttScreenBackground()
        .navigationTitle("sidebar.more")
    }

    /// Areas that exist in the web app only (reports, evaluation/export): one honest row each instead of a dead end.
    @ViewBuilder private var webAreas: some View {
        let rows = webRows
        if let url = model.serverURL, !rows.isEmpty {
            FormSection("Im Web", footer: "Diese Bereiche gibt es noch nicht in der App. Sie öffnen die Web-App auf deinem Server.") {
                ForEach(rows, id: \.id) { row in
                    Link(destination: url) {
                        SettingsRowLabel(title: row.title, symbol: row.symbol, value: nil, chevron: "arrow.up.right")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(row.id)
                    .accessibilityHint(Text("Öffnet die Web-App im Browser"))
                }
            }
        }
    }

    private var webRows: [(id: String, title: LocalizedStringKey, symbol: String)] {
        var rows: [(id: String, title: LocalizedStringKey, symbol: String)] = []
        if model.isEnabled(.reports) { rows.append(("more.reports", "Berichtsheft", "book.closed")) }
        if model.isEnabled(.transfer) { rows.append(("more.export", "Auswertung und Export", "square.and.arrow.up")) }
        // Freigaben exist natively since PL1 (Zeit › Mehr); they join this list when "Planung" is merged (UX3 follow-up).
        return rows
    }

    private var remindersGroup: some View {
        FormSection("Erinnerungen") {
            if model.isEnabled(.planning) {
                SettingsLinkRow(title: "Urlaubserinnerungen", symbol: "bell.badge", id: "settings.reminders") { VacationReminderSettingsView() } // R3
            }
            SettingsLinkRow(title: "Überstunden-Hinweise", symbol: "clock.badge.exclamationmark", id: "settings.overwork") { OverworkSettingsView() } // OT1
        }
    }

    /// What the app does on its own or with other apps: device calendars, location automation, Focus filter (moved here from the settings, S2).
    private var automationGroup: some View {
        FormSection("Automatik und Kalender", footer: model.isEnabled(.automation) ? "settings.focus.hint" : nil) {
            SettingsLinkRow(title: "Kalender", symbol: "calendar", id: "settings.calendar") { CalendarSettingsView() }
            if model.isEnabled(.automation) { // L2/F2: hidden when the automation module is off (account or server-wide)
                SettingsLinkRow(title: "Standortautomatik", symbol: "location.circle", id: "settings.automation") { AutomationSettingsView() }
                SettingsLinkRow(title: "settings.focus", symbol: "moon.circle", id: "settings.focus") { FocusFilterView() }
            }
        }
    }
}
