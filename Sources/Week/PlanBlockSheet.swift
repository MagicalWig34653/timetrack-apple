#if os(iOS)
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// U2: sheet of one plan block in the graphical planner: kind (colour, icon, pattern), times, place, note, split, merge, delete.
/// "Übernehmen" writes everything back as one edit; split, merge and delete act at once.
struct PlanBlockSheet: View {
    let store: WeekPlanStore
    let ref: BlockRef
    let places: [Place]
    @Environment(\.dismiss) private var dismiss

    @State private var kind: PlanBlockKind = .work
    @State private var start = "08:00"
    @State private var end = "12:00"
    @State private var placeId: UUID?
    @State private var note = ""
    @State private var loaded = false

    private var block: PlanTimeBlock? { store.drafts[safe: ref.day]?.blocks[safe: ref.index] }
    private var title: String { store.days[safe: ref.day].map { dayTitle($0.date, calendar: store.calendar) } ?? "" }
    private var startMinutes: Int? { WeekPlan.parseClock(start) }
    private var endMinutes: Int? { WeekPlan.parseClock(end) }
    private var valid: Bool { (startMinutes ?? 0) < (endMinutes ?? 0) && startMinutes != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: TT.Space.s)], spacing: TT.Space.s) {
                        ForEach(PlanBlockKind.selectable, id: \.self) { option in
                            Button { kind = option; TTHaptics.play(.selection) } label: {
                                HStack(spacing: 6) {
                                    PlanKindSwatch(kind: option, size: 24)
                                    Text(verbatim: option.title).font(TTFont.body).foregroundStyle(TT.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .background(kind == option ? option.tint.opacity(0.22) : TT.surfaceRaised, in: .rect(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(kind == option ? option.tint : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(kind == option ? .isSelected : [])
                            .accessibilityIdentifier("plan.sheet.kind.\(option.rawValue)")
                        }
                    }
                } header: { Text(verbatim: "Art") }
                Section {
                    PlanClockPicker(title: "Beginn", value: start, fallback: 8 * 60) { start = WeekPlan.formatClock($0) }
                    PlanClockPicker(title: "Ende", value: end, fallback: 12 * 60) { end = WeekPlan.formatClock($0) }
                    if !valid { Label { Text(verbatim: "Das Ende muss nach dem Beginn liegen.") } icon: { Image(systemName: "exclamationmark.triangle.fill") }.font(TTFont.meta).foregroundStyle(TT.danger) }
                } header: { Text(verbatim: "Zeit") }
                if !places.isEmpty {
                    Section {
                        Picker(selection: $placeId) {
                            Text(verbatim: "Kein Ort").tag(UUID?.none)
                            ForEach(places.filter { !$0.archived }) { place in Text(verbatim: place.name).tag(UUID?.some(place.id)) }
                        } label: { Text(verbatim: "Ort") }
                    }
                }
                Section {
                    TextField("Notiz zum Block", text: $note, axis: .vertical).lineLimit(1...3).accessibilityIdentifier("plan.sheet.note")
                } header: { Text(verbatim: "Notiz") }
                Section {
                    Button { store.splitBlock(ref.day, at: ref.index); dismiss() } label: { Label("Teilen", systemImage: "scissors") }
                        .disabled(!PlanBlockEditing.canSplit(store.drafts[safe: ref.day]?.blocks ?? [], at: ref.index))
                    Button { store.mergeBlock(ref.day, at: ref.index); dismiss() } label: { Label("Mit nächstem verbinden", systemImage: "arrow.triangle.merge") }
                        .disabled(!PlanBlockEditing.canMerge(store.drafts[safe: ref.day]?.blocks ?? [], at: ref.index))
                    Button(role: .destructive) { store.eraseBlock(ref.day, at: ref.index); dismiss() } label: { Label("Block löschen", systemImage: "trash") }
                        .accessibilityIdentifier("plan.sheet.delete")
                }
            }
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Übernehmen") { apply() }.disabled(!valid).accessibilityIdentifier("plan.sheet.apply") }
            }
            .onAppear {
                guard !loaded, let block else { return }
                loaded = true
                kind = block.kind == .unknown ? .work : block.kind
                start = block.start
                end = block.end
                placeId = block.placeId
                note = block.note ?? ""
            }
        }
    }

    private func apply() {
        guard let block, let s = startMinutes, let e = endMinutes, e > s else { return }
        var index = ref.index
        if block.start != start || block.end != end {
            index = store.moveBlock(from: ref.day, at: ref.index, toDay: ref.day, range: MinuteRange(start: s, end: e)) ?? index
        }
        store.setBlockDetails(ref.day, at: index, kind: kind, placeId: placeId, note: note)
        dismiss()
    }
}

/// U2: copies the plan of one day onto other days of the week (blocked days are not offered).
struct CopyDaySheet: View {
    let store: WeekPlanStore
    let source: Int
    @Environment(\.dismiss) private var dismiss
    @State private var targets: Set<Int> = []

    private var candidates: [Int] { (0..<7).filter { $0 != source && !(store.days[safe: $0]?.isBlocked ?? true) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates, id: \.self) { i in
                        Button {
                            if targets.contains(i) { targets.remove(i) } else { targets.insert(i) }
                        } label: {
                            HStack {
                                Text(verbatim: store.days[safe: i].map { dayTitle($0.date, calendar: store.calendar) } ?? "").foregroundStyle(TT.textPrimary)
                                Spacer()
                                if targets.contains(i) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityAddTraits(targets.contains(i) ? .isSelected : [])
                    }
                } header: { Text(verbatim: "Plan von \(store.days[safe: source].map { dayTitle($0.date, calendar: store.calendar) } ?? "") kopieren nach") }
                Section {
                    Button("Alle Werktage") { targets = Set(candidates.filter { (store.days[safe: $0]?.targetSeconds ?? 0) > 0 }) }
                }
            }
            .navigationTitle(Text(verbatim: "Tag kopieren"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kopieren") { store.copyDay(source, to: targets.sorted()); dismiss() }.disabled(targets.isEmpty).accessibilityIdentifier("plan.copy.apply")
                }
            }
        }
    }
}
#endif
