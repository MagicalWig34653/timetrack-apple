import SwiftUI
import TimetrackCore
import TimetrackDesign

/// AD1: inspector column of the Mac "Zeit" screen: details of the selected segment(s) with edit/void actions.
struct SegmentInspector: View {
    let segments: [Segment]
    let zone: TimeZone
    let edit: () -> Void
    let void: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                switch segments.count {
                case 0:
                    EmptyState(symbol: "cursorarrow.click", title: LocalizedStringKey(AD.s("inspector.none")), message: LocalizedStringKey(AD.s("inspector.none.hint")))
                case 1:
                    single(segments[0])
                default:
                    many
                }
            }
            .padding(TT.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ttScreenBackground()
        .accessibilityIdentifier("time.inspector")
    }

    private func range(_ start: Date, _ end: Date?) -> String {
        "\(start.clockText(in: zone)) – \(end.map { $0.clockText(in: zone) } ?? "…")"
    }

    private func duration(_ segment: Segment) -> String {
        segment.endedAt.map { DurationFormat.hoursMinutes(Int($0.timeIntervalSince(segment.startedAt))) } ?? "…"
    }

    @ViewBuilder private func single(_ segment: Segment) -> some View {
        HStack(spacing: TT.Space.m) {
            KindGlyph(symbol: segment.kind.symbol, tint: segment.kind.ttTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.kind.titleKey).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                Text(verbatim: segment.startedAt.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.wide)))
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
        }
        FormSection {
            FormRow(LocalizedStringKey(AD.s("inspector.time"))) { Text(verbatim: range(segment.startedAt, segment.endedAt)).monospacedDigit() }
            FormRow(LocalizedStringKey(AD.s("inspector.duration"))) { Text(verbatim: duration(segment)).monospacedDigit() }
            // Raw time and corrected/rounded evaluation are kept apart (project rule): show the raw time when it differs.
            if segment.rawStartedAt != segment.startedAt || segment.rawEndedAt != segment.endedAt {
                FormRow(LocalizedStringKey(AD.s("inspector.raw"))) { Text(verbatim: range(segment.rawStartedAt, segment.rawEndedAt)).monospacedDigit() }
            }
            if let revisions = segment.revisions, revisions > 0 {
                FormRow(LocalizedStringKey(AD.s("inspector.revisions"))) { Text(verbatim: "\(revisions)") }
            }
        }
        if let note = segment.note, !note.isEmpty {
            FormSection("editor.note") {
                Text(verbatim: note).textSelection(.enabled).padding(TT.Space.m).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if segment.needsReview { StatusChip(LocalizedStringKey(AD.s("inspector.needs_review")), tone: .warning) }
        if segment.isRunning { StatusChip("today.running", tone: .accent) }
        actions
    }

    @ViewBuilder private var many: some View {
        let total = segments.reduce(0) { $0 + Int(($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) }
        Text(AD.s("inspector.many \(segments.count)")).font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
        FormSection {
            FormRow(LocalizedStringKey(AD.s("inspector.duration"))) { Text(verbatim: DurationFormat.hoursMinutes(total)).monospacedDigit() }
        }
        Button(role: .destructive, action: void) { Label("time.void", systemImage: "trash") }
            .buttonStyle(.ttSecondary).foregroundStyle(TT.danger)
    }

    private var actions: some View {
        VStack(spacing: TT.Space.s) {
            Button(action: edit) { Label("time.edit", systemImage: "pencil").frame(maxWidth: .infinity) }
                .buttonStyle(.ttPrimary)
                .disabled(segments.first?.isRunning == true)
            Button(role: .destructive, action: void) { Label("time.void", systemImage: "trash").frame(maxWidth: .infinity) }
                .buttonStyle(.ttSecondary).foregroundStyle(TT.danger)
        }
    }
}
