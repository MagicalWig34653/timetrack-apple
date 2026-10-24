import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Q1: "n zu prüfen" on "Heute" and in the "Jetzt" sheet. The count comes from the review list (all recent days, minus what the user has
/// dealt with), not from today's segments only. On iPhone/iPad a tap opens the list with the reason and the fix actions; on the Mac it opens the sidebar screen
/// "Zu prüfen" (SG1).
struct ReviewChip: View {
    /// Fallback until the review list has loaded, and when the store is missing.
    let todaysFlagged: Int
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var opened = false
    #if os(macOS)
    @Environment(UIState.self) private var ui
    #endif

    private var count: Int {
        guard let review = model.review, review.hasLoaded else { return todaysFlagged }
        return review.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if count > 0 { chip }
        }
        .task { await model.review?.load() }
        .onChange(of: todaysFlagged) { Task { await model.review?.load() } }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.review?.load() } } }
    }

    private var label: String { String(localized: "h3.review \(count)", table: "UX3") }

    @ViewBuilder private var chip: some View {
        #if os(iOS)
        Button { opened = true } label: {
            HStack(spacing: 4) {
                StatusChip(verbatim: label, tone: .warning, symbol: "exclamationmark.circle")
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(TT.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, -6)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityHint(Text(LocalizedStringResource("q1.review.hint", table: "Q1")))
        .accessibilityIdentifier("today.review")
        .sheet(isPresented: $opened) { ReviewSheet() }
        #else
        // SG1: on the Mac the chip opens the sidebar screen "Zu prüfen" (suggestions and flagged entries).
        Button { ui.selection = .suggestions } label: {
            HStack(spacing: 4) {
                StatusChip(verbatim: label, tone: .warning, symbol: "exclamationmark.circle")
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(TT.textTertiary).accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityHint(Text(LocalizedStringResource("q1.review.hint", table: "Q1")))
        .accessibilityIdentifier("today.review")
        #endif
    }
}
