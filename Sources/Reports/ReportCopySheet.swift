import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// "Kopieren für IHK-Portal": preview of the text in the backend's standard format, a copy button (plain text plus a rich variant
/// in one go) and the system share sheet. The backend offers no PDF or other export for the Berichtsheft, so none is shown.
struct ReportCopySheet: View {
    let store: ReportsStore
    @Environment(\.dismiss) private var dismiss
    @State private var payload: ReportsStore.CopyPayload?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    Text(verbatim: BH.s("copy.intro")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    if let payload {
                        if payload.isEmpty {
                            Card { EmptyState(symbol: "doc.text", title: LocalizedStringKey(BH.s("copy.empty"))) }
                        } else {
                            Card {
                                Text(verbatim: payload.plain).font(.system(.footnote, design: .monospaced)).foregroundStyle(TT.textPrimary)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel(Text(verbatim: BH.s("copy.text_label")))
                                    .accessibilityIdentifier("reports.copy.text")
                            }
                            Button { ReportPasteboard.copy(plain: payload.plain, html: payload.html); copied = true; TTHaptics.play(.success) } label: {
                                Label(BH.s(copied ? "copy.done" : "copy.action"), systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.ttPrimary).accessibilityIdentifier("reports.copy.action")
                            .keyboardShortcut("c", modifiers: [.command, .shift])
                            ShareLink(item: payload.plain, subject: Text(verbatim: BH.s("copy.subject", store.week.week, store.week.year))) {
                                Label(BH.s("copy.share"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.ttSecondary).accessibilityIdentifier("reports.copy.share")
                            Text(verbatim: BH.s("copy.rich_note")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        }
                    } else {
                        SkeletonList(rows: 4)
                    }
                }
                .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(BH.s("copy.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(BH.s("common.done")) { dismiss() }.accessibilityIdentifier("reports.copy.done") } }
        }
        .task { payload = await store.copyPayload() }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #else
        .presentationDetents([.large])
        #endif
    }
}
