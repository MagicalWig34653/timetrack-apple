import SwiftUI
import TimetrackCore

/// All components on one page with synthetic data. Used by previews and by the macOS image render test.
public struct DesignGallery: View {
    @State private var kind: SegmentKind = .work
    private let running: Bool
    private let scrollable: Bool

    public init(running: Bool = false, scrollable: Bool = true) {
        self.running = running
        self.scrollable = scrollable
    }

    public var body: some View {
        if scrollable { ScrollView { column }.ttScreenBackground().ttTheme() } else { column.ttScreenBackground().ttTheme() }
    }

    private var column: some View {
            VStack(alignment: .leading, spacing: TT.Space.xl) {
                TimerHero(startedAt: running ? Date.now.addingTimeInterval(-4521) : nil, kind: kind,
                          idleTitle: "Kein Zeitabschnitt läuft", idleSubtitle: "Wähle eine Art und starte.", runningCaption: "Läuft") {
                    if running {
                        Button { } label: { Label("Stoppen", systemImage: "stop.fill") }.buttonStyle(.ttDanger).controlSize(.large)
                    } else {
                        KindSelector(selection: $kind)
                        Button { } label: { Label("Starten", systemImage: "play.fill") }.buttonStyle(.ttPrimary).controlSize(.large)
                    }
                }
                Card {
                    HStack(spacing: TT.Space.l) {
                        ProgressRing(progress: 0.68, lineWidth: 12) { Text(verbatim: "68 %").font(TTFont.statSmall) }.frame(width: 96, height: 96)
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(verbatim: "Erfasst")
                            Text(verbatim: "5:12").font(TTFont.stat)
                            ProgressBar(progress: 0.68)
                            StatusChip(verbatim: "vorläufig", tone: .warning)
                        }
                    }
                }
                HStack(spacing: TT.Space.m) {
                    StatTile("Differenz", value: "-2:30", chip: "vorläufig", tone: .warning)
                    StatTile("Zeitkonto", value: "+12:45", caption: "Stand heute", tone: .success)
                }
                SectionHeader("Zeitabschnitte heute") { Text(verbatim: "3") }
                ListCard {
                    SegmentRowCell(kind: .work, timeRange: "08:00 – 12:15", duration: "4:15", note: "Kundentermin")
                    SegmentRowCell(kind: .travel, timeRange: "12:30 – 13:00", duration: "0:30")
                    SegmentRowCell(kind: .school, timeRange: "13:15 – …", duration: nil, isRunning: true, needsReview: true)
                }
                HStack(spacing: TT.Space.s) {
                    StatusChip(verbatim: "genehmigt", tone: .success, symbol: "checkmark")
                    StatusChip(verbatim: "beantragt", tone: .accent)
                    StatusChip(verbatim: "abgelehnt", tone: .danger)
                    KindBadge(.travel)
                }
                FormSection(footer: "Hilfetext unter dem Abschnitt.") {
                    FormRow("Server") { Text(verbatim: "zeit.example.org") }
                    FormRow("Zeitzone") { Text(verbatim: "Europe/Berlin") }
                }
                ErrorBanner(message: "Der Server ist nicht erreichbar.", retryTitle: "Erneut versuchen") {}
                HintBanner("Hinweis: Bei mehr als 6 Stunden Arbeit sind 30 Minuten Pause vorgesehen.", symbol: "cup.and.saucer.fill")
                EmptyState(symbol: "calendar", title: "Keine Einträge", message: "Hier erscheinen deine Zeitabschnitte.")
                SkeletonList(rows: 2)
                HStack {
                    Button("Sekundär") {}.buttonStyle(.ttSecondary)
                }
            }
            .padding(TT.Space.l)
            .frame(maxWidth: TT.contentWidth)
            .frame(maxWidth: .infinity)
    }
}

#Preview("Gallery light") { DesignGallery() }
#Preview("Gallery dark running") { DesignGallery(running: true).preferredColorScheme(.dark) }
#Preview("Gallery large type") { DesignGallery().dynamicTypeSize(.accessibility2) }
#Preview("Reduce transparency") { DesignGallery(running: true).environment(\.ttSolidSurfaces, true) }
