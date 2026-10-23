import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// H4: "Fortführen: Arbeit, zuletzt bis 12:03" – continues the most recent finished entry of today (reopen, or a new entry from now when
/// the server cannot reopen). Shown only while idle and when such an entry exists.
struct ContinueButton: View {
    let store: TodayStore
    var onDone: () -> Void = {}
    @Environment(AppModel.self) private var model
    @State private var busy = false
    @State private var choosing = false

    private func run(startNew: Bool) {
        busy = true
        Task { await store.continueLast(startNew: startNew); busy = false; onDone() }
    }

    var body: some View {
        if let segment = store.continuableSegment, let ended = segment.endedAt {
            let until = ended.formatted(Date.FormatStyle(timeZone: model.dayCalendar.timeZone).hour().minute())
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let gap = max(0, context.date.timeIntervalSince(ended))
                let long = gap > TodayStore.longContinueGap
                VStack(spacing: TT.Space.xs) {
                    Button { if long { choosing = true } else { run(startNew: false) } } label: {
                        Label { ux3("h4.continue \(segment.kind.plainName) \(until)") } icon: { Image(systemName: "arrow.uturn.forward") }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttSecondary).controlSize(.large).disabled(busy)
                    .accessibilityHint(ux3("h4.continue.hint"))
                    .accessibilityIdentifier("continue.last")
                    if gap >= 60 {
                        (segment.kind == .work ? ux3("h4.gap.work \(DurationFormat.hoursMinutes(Int(gap)))") : ux3("h4.gap.other \(DurationFormat.hoursMinutes(Int(gap)))"))
                            .font(TTFont.meta).foregroundStyle(TT.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("continue.gap")
                    }
                }
                .confirmationDialog(ux3String("h4.continue.choose \(DurationFormat.hoursMinutes(Int(gap)))"), isPresented: $choosing, titleVisibility: .visible) {
                    Button(ux3String("h4.continue.with_gap")) { run(startNew: false) }
                    Button(ux3String("h4.continue.fresh")) { run(startNew: true) }
                    Button(role: .cancel) {} label: { Text("common.cancel") }
                }
            }
        }
    }
}

/// H4: says honestly which of the three outcomes happened (reopened / new entry, gap stays a pause / waiting for delivery); fades after a while.
struct ContinueNotice: View {
    let store: TodayStore

    var body: some View {
        if let notice = store.continueNotice {
            HStack(alignment: .top, spacing: TT.Space.s) {
                Image(systemName: notice == .startedNew ? "info.circle" : "checkmark.circle").foregroundStyle(TT.textSecondary).accessibilityHidden(true)
                switch notice {
                case .reopened: ux3("h4.notice.reopened")
                case .startedNew: ux3("h4.notice.started_new")
                case .queued: ux3("h4.notice.queued")
                }
            }
            .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("continue.notice")
            .task(id: notice) {
                try? await Task.sleep(for: .seconds(notice == .startedNew ? 12 : 6))
                if !Task.isCancelled { store.clearContinueNotice() }
            }
        }
    }
}
