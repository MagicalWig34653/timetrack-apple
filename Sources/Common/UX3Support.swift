import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// UX3: pieces shared by the iOS/iPadOS and macOS apps. Strings live in their own table (`UX3.xcstrings`) so parallel packages
// editing the big catalogs do not conflict. Wording follows docs/glossary-ui.md.

/// Text from the UX3 table.
func ux3(_ key: String.LocalizationValue) -> Text { Text(LocalizedStringResource(key, table: "UX3")) }

/// Plain String from the UX3 table (accessibility labels, menus).
func ux3String(_ key: String.LocalizationValue) -> String { String(localized: key, table: "UX3") }

// MARK: - Day standing card ("Heute")

/// The day card of "Heute": one ring, one worked-time figure and one sentence about the target; the time account below.
/// Replaces ring percentage + "Erfasst" + "Differenz" tile, which said the same thing three times (UX1 F07).
struct DayStandingCard: View {
    let store: TodayStore
    /// H3: also show the expected end, the break status and open review items (iPhone "Heute" and the "Jetzt" sheet).
    var showsOutlook = false
    /// H3: the sheet shows the card without the time account tile and without the term explainer.
    var showsBalance = true
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var explaining = false

    var body: some View {
        let day = store.day
        let done = (day?.evaluatedWorkSeconds ?? 0) + (day?.creditSeconds ?? 0)
        let hasStarted = store.running != nil || !store.segments.isEmpty
        let standing = DayStanding(doneSeconds: done, targetSeconds: day?.targetSeconds ?? 0, hasStarted: hasStarted)
        VStack(spacing: TT.Space.m) {
            Card {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: TT.Space.l)) : AnyLayout(HStackLayout(spacing: TT.Space.xl))
                layout {
                    if standing.showsRing {
                        ProgressRing(progress: standing.progress, lineWidth: 12, tint: ringTint(standing)) {
                            if case .reached = standing.status { Image(systemName: "checkmark").font(.title2.weight(.semibold)).foregroundStyle(TT.success) }
                            else if case .over = standing.status { Image(systemName: "checkmark").font(.title2.weight(.semibold)).foregroundStyle(TT.success) }
                        }
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: TT.Space.xs) {
                        HStack(spacing: TT.Space.xs) {
                            Text("today.done").font(TTFont.label).foregroundStyle(TT.textSecondary)
                            Button { explaining = true } label: {
                                Image(systemName: "info.circle").imageScale(.small).foregroundStyle(TT.textTertiary)
                                    .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, -14) // keeps the 44 pt target without making the label row tall
                            .accessibilityLabel(ux3("ux3.terms.button"))
                            .accessibilityIdentifier("today.terms")
                            .popover(isPresented: $explaining) { TermsExplainer().presentationCompactAdaptation(.popover) }
                        }
                        Text(verbatim: DurationFormat.hoursMinutes(done))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(TT.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        standingLine(standing)
                        if showsOutlook { outlookBlock }
                        if day?.provisional == true || store.account?.provisional == true { ProvisionalChip() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            if showsBalance {
                StatTile("today.balance", value: DurationFormat.signed(store.account?.balanceSeconds ?? 0), symbol: "clock.arrow.circlepath")
                    .accessibilityIdentifier("today.balance")
            }
        }
    }

    /// H3: expected end, break status, day mark and entries that need a look; refreshed every 30 s (live while a timer runs).
    @ViewBuilder private var outlookBlock: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: TT.Space.xs) {
                DayOutlookLines(outlook: store.outlook(now: context.date), zone: model.dayCalendar.timeZone)
                    .padding(.top, TT.Space.xs)
                ReviewChip(todaysFlagged: store.segments.filter(\.needsReview).count)
            }
        }
    }

    private func ringTint(_ standing: DayStanding) -> Color? {
        switch standing.status {
        case .reached, .over: TT.success
        default: nil
        }
    }

    @ViewBuilder private func standingLine(_ standing: DayStanding) -> some View {
        Group {
            switch standing.status {
            case .noTarget: ux3("ux3.standing.no_target")
            case .notStarted: ux3("ux3.standing.not_started \(DurationFormat.hoursMinutes(standing.targetSeconds))")
            case .remaining(let seconds): ux3("ux3.standing.remaining \(DurationFormat.hoursMinutes(standing.targetSeconds)) \(DurationFormat.hoursMinutes(seconds))")
            case .reached: ux3("ux3.standing.reached \(DurationFormat.hoursMinutes(standing.targetSeconds))")
            case .over(let seconds): ux3("ux3.standing.over \(DurationFormat.hoursMinutes(standing.targetSeconds)) \(DurationFormat.hoursMinutes(seconds))")
            }
        }
        .font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("today.standing")
    }
}

/// "vorläufig" with its explanation one tap away.
struct ProvisionalChip: View {
    @State private var explaining = false

    var body: some View {
        Button { explaining = true } label: { StatusChip("common.provisional", tone: .neutral, symbol: "info.circle") }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityHint(ux3("ux3.provisional.hint"))
            .popover(isPresented: $explaining) {
                VStack(alignment: .leading, spacing: TT.Space.s) {
                    Text("common.provisional").font(TTFont.cardTitle)
                    ux3("ux3.provisional.explain").font(TTFont.body).foregroundStyle(TT.textSecondary)
                }
                .padding(TT.Space.l).frame(maxWidth: 320)
                .presentationCompactAdaptation(.popover)
            }
    }
}

/// The four terms of the day card in plain words (glossary).
struct TermsExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.m) {
            term("today.done", "ux3.terms.worked")
            term("today.target", "ux3.terms.target")
            term("today.balance", "ux3.terms.balance")
            term("common.provisional", "ux3.terms.provisional")
        }
        .padding(TT.Space.l).frame(maxWidth: 340, alignment: .leading)
    }

    private func term(_ title: LocalizedStringKey, _ explanation: String.LocalizationValue) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(TTFont.label).foregroundStyle(TT.textPrimary)
            ux3(explanation).font(TTFont.meta).foregroundStyle(TT.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Sync status line

/// Small line under the title that appears only when something is unusual: actions wait for delivery, or the server is unreachable.
/// Silent when all is well (a permanent "alles in Ordnung" would be noise).
struct SyncStatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let store = model.today, store.syncStatus != .ok {
            let status = store.syncStatus
            HStack(spacing: TT.Space.s) {
                Image(systemName: symbol(status)).imageScale(.small).accessibilityHidden(true)
                text(status).font(TTFont.meta).lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(tone(status))
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.xs)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(.bar)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sync.status")
        }
    }

    private func symbol(_ status: SyncStatus) -> String {
        switch status {
        case .offline: "wifi.slash"
        default: "arrow.triangle.2.circlepath"
        }
    }

    private func tone(_ status: SyncStatus) -> Color {
        if case .offline = status { return TT.warning }
        return TT.textSecondary
    }

    private func text(_ status: SyncStatus) -> Text {
        switch status {
        case .ok: Text(verbatim: "")
        case .sending(let count): ux3("ux3.sync.sending \(count)")
        case .offline(let pending): pending > 0 ? ux3("ux3.sync.offline_pending \(pending)") : ux3("ux3.sync.offline")
        }
    }
}

extension View {
    /// Status line above the content of a screen (below the navigation bar).
    func ttSyncStatusLine() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { SyncStatusLine() }
    }
}
