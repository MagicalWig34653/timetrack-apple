import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// UX3: "Mehr" replaces the "Einstellungen" tab as the place for everything that is not part of the daily path: areas the app does not
/// have natively yet (they open the web app), reminders, automation and the settings themselves. The S2 settings pages stay as they are.
struct MoreView: View {
    @Environment(AppModel.self) private var model
    @State private var showReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                AccountCard()
                reviewGroup
                reportsGroup
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
        .sheet(isPresented: $showReview) { ReviewSheet() }
    }

    /// SG1: what waits for a decision (suggestions of the automation, flagged entries) and the bin of cancelled entries.
    private var reviewGroup: some View {
        let count = model.review?.count ?? 0
        return FormSection("Prüfen und Storniert", footer: "Vorschläge der Automatik und Einträge, die einen Blick brauchen. Nichts wird ohne dein Zutun gebucht. Stornierte Einträge kannst du wiederherstellen oder endgültig löschen.") {
            SettingsActionRow(title: "Zu prüfen", symbol: "checklist", id: "more.review") { showReview = true }
                .overlay(alignment: .trailing) {
                    if count > 0 {
                        Text(verbatim: "\(count)").font(TTFont.meta.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(TT.warning, in: .capsule)
                            .padding(.trailing, 36).accessibilityHidden(true)
                    }
                }
                .accessibilityValue(count > 0 ? Text(verbatim: SG1.s("sg1.badge.label \(count)")) : Text(verbatim: ""))
            SettingsLinkRow(title: "Storniert", symbol: "trash", id: "more.cancelled") { CancelledScreen() }
        }
    }

    /// BH1: the Berichtsheft is native now (weeks, entries, learning fields, copy for the IHK portal).
    @ViewBuilder private var reportsGroup: some View {
        if model.isEnabled(.reports) {
            FormSection("Ausbildung", footer: "Wochenberichte für die Ausbildung: Lernfeld, Zeit und Notizen, kopierbar für das IHK-Portal.") {
                SettingsLinkRow(title: "Berichtsheft", symbol: "book.closed", id: "more.reports") { ReportsScreen() }
            }
        }
    }

    /// Areas that exist in the web app only (evaluation/export): one honest row each instead of a dead end.
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
