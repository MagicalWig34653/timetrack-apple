import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// U3: "Mehr" is the launcher for features that are not part of the daily path (Prüfen, Storniert, Statistik, Berichtsheft, Orte, Web areas).
/// Everything that is configured (account, appearance, work, reminders, calendar, automation, Focus, info) lives in "Einstellungen" only.
struct MoreView: View {
    @Environment(AppModel.self) private var model
    @State private var showReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                reviewGroup
                evaluationGroup
                reportsGroup
                webAreas
                placesGroup
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

    /// WM2: charts of the time account, target vs. worked, kinds, absences and breaks.
    private var evaluationGroup: some View {
        FormSection(wmKey("wm.more.evaluation")) {
            SettingsLinkRow(title: wmKey("wm.stats.title"), symbol: "chart.xyaxis.line", id: "more.statistics") { StatisticsScreen() }
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
                    Link(destination: url.appending(path: row.path)) { // AUD3: the PWA route of the page, not the start page
                        SettingsRowLabel(title: row.title, symbol: row.symbol, value: nil, chevron: "arrow.up.right")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(row.id)
                    .accessibilityHint(Text("Öffnet die Web-App im Browser"))
                }
            }
        }
    }

    private var webRows: [(id: String, title: LocalizedStringKey, symbol: String, path: String)] {
        var rows: [(id: String, title: LocalizedStringKey, symbol: String, path: String)] = []
        if model.isEnabled(.transfer) { rows.append(("more.export", "Auswertung und Export", "square.and.arrow.up", "export")) }
        // Freigaben exist natively since PL1 (Zeit › Mehr); they join this list when "Planung" is merged (UX3 follow-up).
        return rows
    }

    /// U3: places are a feature (list, archive, per-place automation mode); the global automation switches are in the settings.
    @ViewBuilder private var placesGroup: some View {
        if model.isEnabled(.automation) {
            FormSection("Orte", footer: "Deine Orte und was die Automatik dort tut. Archivierte Orte werden von der Automatik ignoriert.") {
                SettingsLinkRow(title: "Orte und Automatik", symbol: "mappin.and.ellipse", id: "more.places") { AutomationSettingsView() }
            }
        }
    }
}
