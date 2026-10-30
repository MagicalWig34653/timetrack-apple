import SwiftUI
import TimetrackCore
import TimetrackDesign

// P13 (contract 0.35.0, ADR-0031): several plan blocks per day. Shared by iOS, iPadOS and macOS.
// A plan block is a plan, not worked time. Kinds are recognisable without colour: icon, pattern and text.

// MARK: - Kind presentation

enum PlanBlockPattern { case solid, stripes, dots, lines, crosshatch }

extension PlanBlockKind {
    var title: String {
        switch self {
        case .work, .unknown: "Arbeit"
        case .school: "Schule"
        case .travel: "Fahrt"
        case .office: "Büro"
        case .home: "Homeoffice"
        case .customer: "Kunde"
        }
    }

    var symbol: String {
        switch self {
        case .work, .unknown: "briefcase.fill"
        case .school: "graduationcap.fill"
        case .travel: "car.fill"
        case .office: "building.2.fill"
        case .home: "house.fill"
        case .customer: "person.2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .work, .unknown: TT.kindWork
        case .school: TT.kindSchool
        case .travel: TT.kindTravel
        case .office: PlanMode.office.tint
        case .home: TT.kindExcused
        case .customer: Color(light: 0xBE185D, dark: 0xF472B6)
        }
    }

    var pattern: PlanBlockPattern {
        switch self {
        case .work, .unknown, .office: .solid
        case .school: .stripes
        case .travel: .dots
        case .home: .lines
        case .customer: .crosshatch
        }
    }
}

/// "08:00–12:00 Schule · 13:00–17:00 Arbeit" for lists; the spoken form reads "von … bis … Uhr".
enum PlanBlockText {
    static func line(_ block: PlanTimeBlock) -> String { "\(block.start)–\(block.end) \(block.kind.title)" }
    static func summary(_ blocks: [PlanTimeBlock]) -> String { blocks.map(line).joined(separator: " · ") }
    static func spoken(_ blocks: [PlanTimeBlock]) -> String {
        blocks.map { "\($0.kind.title) von \($0.start) bis \($0.end) Uhr" }.joined(separator: ", ")
    }
    /// A day shows its blocks one by one when there is more than a plain window (several blocks, or a block that is not "work-like").
    static func showsDetail(_ blocks: [PlanTimeBlock]) -> Bool { blocks.count > 1 }
}

// MARK: - Pattern

struct PlanPatternOverlay: View {
    let pattern: PlanBlockPattern

    var body: some View {
        Canvas { context, size in
            let ink = GraphicsContext.Shading.color(.white.opacity(0.55))
            switch pattern {
            case .solid:
                break
            case .stripes:
                var x: CGFloat = -size.height
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(path, with: ink, lineWidth: 1.6)
                    x += 6
                }
            case .dots:
                var y: CGFloat = 3
                while y < size.height {
                    var x: CGFloat = 3
                    while x < size.width {
                        context.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)), with: ink)
                        x += 6
                    }
                    y += 6
                }
            case .lines:
                var y: CGFloat = 3
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: ink, lineWidth: 1.2)
                    y += 5
                }
            case .crosshatch:
                var x: CGFloat = -size.height
                while x < size.width {
                    var up = Path(), down = Path()
                    up.move(to: CGPoint(x: x, y: size.height)); up.addLine(to: CGPoint(x: x + size.height, y: 0))
                    down.move(to: CGPoint(x: x, y: 0)); down.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    context.stroke(up, with: ink, lineWidth: 1)
                    context.stroke(down, with: ink, lineWidth: 1)
                    x += 7
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Small legend swatch: colour, pattern and icon of one kind.
struct PlanKindSwatch: View {
    let kind: PlanBlockKind
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(kind.tint)
            .overlay(PlanPatternOverlay(pattern: kind.pattern).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)))
            .overlay(Image(systemName: kind.symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white).shadow(color: .black.opacity(0.35), radius: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Timeline

/// The blocks of one day as a strip: colour, pattern and icon per kind; gaps stay empty (a gap is a break or simply nothing).
/// Purely a drawing of the plan, read-only.
struct PlanTimeline: View {
    struct Item: Hashable {
        var start: Int
        var end: Int
        var kind: PlanBlockKind
    }

    let items: [Item]
    var height: CGFloat = 24
    var showsAxis = true
    /// Spoken text; defaults to the block list.
    var spokenLabel: String?

    init(blocks: [PlanTimeBlock], height: CGFloat = 24, showsAxis: Bool = true) {
        items = blocks.compactMap { block in
            guard let s = block.startMinutes, let e = block.endMinutes, e > s else { return nil }
            return Item(start: s, end: e, kind: block.kind)
        }
        self.height = height
        self.showsAxis = showsAxis
        spokenLabel = PlanBlockText.spoken(blocks)
    }

    init(shared blocks: [SharedView.PlanDay.Block], height: CGFloat = 24, showsAxis: Bool = true) {
        items = blocks.compactMap { block in
            guard let s = WeekPlan.parseClock(block.start), let e = WeekPlan.parseClock(block.end), e > s else { return nil }
            return Item(start: s, end: e, kind: block.kind)
        }
        self.height = height
        self.showsAxis = showsAxis
        spokenLabel = blocks.map { "\($0.kind.title) von \($0.start) bis \($0.end) Uhr" }.joined(separator: ", ")
    }

    private var range: (lo: Int, hi: Int) {
        guard let first = items.map(\.start).min(), let last = items.map(\.end).max() else { return (8 * 60, 17 * 60) }
        var lo = first / 60 * 60
        var hi = (last + 59) / 60 * 60
        if hi - lo < 4 * 60 { hi = min(24 * 60, lo + 4 * 60); lo = max(0, hi - 4 * 60) }
        return (lo, hi)
    }

    var body: some View {
        if !items.isEmpty {
            let span = Double(range.hi - range.lo)
            VStack(spacing: TT.Space.xxs) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(TT.separator.opacity(0.5))
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            let x = proxy.size.width * Double(item.start - range.lo) / span
                            let width = max(4, proxy.size.width * Double(item.end - item.start) / span)
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(item.kind.tint)
                                .overlay(PlanPatternOverlay(pattern: item.kind.pattern).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)))
                                .overlay {
                                    if width >= 26 {
                                        Image(systemName: item.kind.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                            .shadow(color: .black.opacity(0.4), radius: 1)
                                    }
                                }
                                .frame(width: width, height: height - 4)
                                .offset(x: x)
                        }
                    }
                }
                .frame(height: height)
                if showsAxis {
                    HStack {
                        Text(verbatim: WeekPlan.formatClock(range.lo))
                        Spacer()
                        Text(verbatim: range.hi >= 24 * 60 ? "24:00" : WeekPlan.formatClock(range.hi))
                    }
                    .font(.caption2).monospacedDigit().foregroundStyle(TT.textTertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Plan: " + (spokenLabel ?? "")))
        }
    }
}

/// Non-binding planning hints (`planHints`), shown as calm German notes. A hint is not a legal evaluation.
struct PlanHintsView: View {
    let hints: [PlanHint]
    var dayTitle: String?

    var body: some View {
        let known = hints.filter { $0.germanText != nil }
        if !known.isEmpty {
            VStack(alignment: .leading, spacing: TT.Space.xs) {
                ForEach(known, id: \.self) { hint in
                    HStack(alignment: .firstTextBaseline, spacing: TT.Space.xs) {
                        Image(systemName: "lightbulb").imageScale(.small).foregroundStyle(TT.warning).accessibilityHidden(true)
                        Text(verbatim: (dayTitle.map { "\($0): " } ?? "") + (hint.germanText ?? "")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("plan.hint.\(hint.rawValue)")
                }
                Text(verbatim: "Planungshinweise sind unverbindlich; die Pausenbewertung richtet sich nach den tatsächlichen Zeiten.")
                    .font(.caption2).foregroundStyle(TT.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// "Plan/Ist −0:30": actual evaluated work plus credit minus the effective planned duration (`planActualDifferenceSeconds`).
struct PlanActualDifferenceChip: View {
    let seconds: Int

    var body: some View {
        let text = seconds == 0 ? "Plan erreicht" : "Ist gegenüber Plan \(DurationFormat.signed(seconds))"
        StatusChip(verbatim: text, tone: seconds >= 0 ? .success : .warning)
            .accessibilityLabel(Text(verbatim: seconds == 0 ? "Ist entspricht dem Plan" : "Ist gegenüber Plan \(DurationFormat.signed(seconds)) Stunden"))
            .accessibilityIdentifier("plan.difference")
    }
}

// MARK: - Editor

/// Clock picker for `HH:mm` showing wall-clock time (no zone arithmetic).
struct PlanClockPicker: View {
    let title: String
    let value: String
    let fallback: Int
    let set: (Int) -> Void

    var body: some View {
        HStack {
            Text(verbatim: title).font(TTFont.label).foregroundStyle(TT.textSecondary).lineLimit(1)
            DatePicker("", selection: Binding(get: { ClockPicker.date(minutes: WeekPlan.parseClock(value) ?? fallback) }, set: { set(ClockPicker.minutes(of: $0)) }),
                       displayedComponents: .hourAndMinute)
                .labelsHidden().environment(\.timeZone, ClockPicker.timeZone).environment(\.locale, Locale(identifier: "de_DE"))
                .accessibilityLabel(Text(verbatim: title))
        }
        .frame(minHeight: 44)
    }
}

/// The block list of one day: add, split, merge with the next block and delete, kind, times, place and note per block.
/// Edits go through `PlanBlockEditing`; the list stays as the user left it (an overlap is named, not silently fixed).
struct PlanBlockEditor: View {
    @Binding var blocks: [PlanTimeBlock]
    let defaultKind: PlanBlockKind
    let places: [Place]
    let idPrefix: String
    @Environment(\.dynamicTypeSize) private var typeSize

    private var problem: DraftProblem? { WeekPlan.blocksProblem(blocks) }

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            if blocks.isEmpty {
                Text(verbatim: "Noch keine Uhrzeiten geplant. Ein Tag ohne Blöcke gilt als grober Plan.").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                PlanTimeline(blocks: blocks).accessibilityIdentifier("\(idPrefix).timeline")
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                row(index, block)
                if index < blocks.count - 1, let gap = PlanBlockEditing.gapMinutes(blocks)[safe: index], gap > 0 {
                    HStack(spacing: TT.Space.xs) {
                        Image(systemName: "cup.and.saucer").imageScale(.small).accessibilityHidden(true)
                        Text(verbatim: "Lücke \(gap) Min.")
                    }
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.leading, TT.Space.s)
                }
            }
            if let problem { Label { Text(verbatim: message(problem)) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                .font(TTFont.meta).foregroundStyle(TT.danger).accessibilityIdentifier("\(idPrefix).problem") }
            Button {
                blocks = PlanBlockEditing.adding(to: blocks, kind: defaultKind)
            } label: { Label("Block hinzufügen", systemImage: "plus.circle").frame(minHeight: 44) }
                .buttonStyle(.borderless).disabled(blocks.count >= PlanBlocks.maxCount).accessibilityIdentifier("\(idPrefix).add")
        }
    }

    private func message(_ problem: DraftProblem) -> String {
        switch problem {
        case .blocksOverlap: "Planblöcke überschneiden sich oder sind nicht der Zeit nach geordnet."
        case .tooManyBlocks: "Höchstens \(PlanBlocks.maxCount) Planblöcke pro Tag."
        case .noteTooLong: "Die Notiz eines Blocks ist zu lang (höchstens \(PlanBlocks.maxNoteLength) Zeichen)."
        case .endBeforeStart: "Das Ende eines Blocks muss nach seinem Beginn liegen."
        case .timesRequired, .breakInvalid: "Beginn und Ende eines Blocks brauchen eine Uhrzeit."
        }
    }

    private func row(_ index: Int, _ block: PlanTimeBlock) -> some View {
        let id = "\(idPrefix).\(index)"
        return VStack(alignment: .leading, spacing: TT.Space.xs) {
            HStack(spacing: TT.Space.s) {
                kindMenu(index, block, id: id)
                Spacer(minLength: TT.Space.s)
                Menu {
                    Button { blocks = PlanBlockEditing.splitting(blocks, at: index) } label: { Label("Teilen", systemImage: "scissors") }
                        .disabled(!PlanBlockEditing.canSplit(blocks, at: index))
                    Button { blocks = PlanBlockEditing.mergingWithNext(blocks, at: index) } label: { Label("Mit nächstem verbinden", systemImage: "arrow.triangle.merge") }
                        .disabled(!PlanBlockEditing.canMerge(blocks, at: index))
                    Divider()
                    Button(role: .destructive) { blocks = PlanBlockEditing.deleting(blocks, at: index) } label: { Label("Block löschen", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").imageScale(.large).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(Text(verbatim: "Aktionen für Block \(index + 1)")).accessibilityIdentifier("\(id).menu")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TT.Space.m) { startPicker(index, block).fixedSize(); endPicker(index, block).fixedSize() }
                VStack(alignment: .leading, spacing: TT.Space.xs) { startPicker(index, block); endPicker(index, block) }
            }
            if !places.isEmpty { placeMenu(index, block, id: id) }
            TextField("Notiz zum Block", text: Binding(get: { blocks[safe: index]?.note ?? "" }, set: { value in
                guard blocks.indices.contains(index) else { return }
                blocks[index].note = value.isEmpty ? nil : String(value.prefix(PlanBlocks.maxNoteLength))
            }))
            .ttField().accessibilityIdentifier("\(id).note")
        }
        .padding(TT.Space.s)
        .background(RoundedRectangle(cornerRadius: TT.Radius.card, style: .continuous).fill(TT.surfaceRaised))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "Block \(index + 1) von \(blocks.count): \(PlanBlockText.line(block))"))
        .accessibilityIdentifier(id)
    }

    private func kindMenu(_ index: Int, _ block: PlanTimeBlock, id: String) -> some View {
        Menu {
            ForEach(PlanBlockKind.selectable, id: \.self) { kind in
                Button { if blocks.indices.contains(index) { blocks[index].kind = kind } } label: { Label(kind.title, systemImage: kind.symbol) }
            }
        } label: {
            HStack(spacing: 6) {
                PlanKindSwatch(kind: block.kind)
                Text(verbatim: block.kind.title).foregroundStyle(TT.textPrimary)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(TT.textSecondary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel(Text(verbatim: "Art des Blocks \(index + 1): \(block.kind.title)")).accessibilityIdentifier("\(id).kind")
    }

    private func startPicker(_ index: Int, _ block: PlanTimeBlock) -> some View {
        PlanClockPicker(title: "Beginn", value: block.start, fallback: 8 * 60) { minutes in
            if blocks.indices.contains(index) { blocks[index].start = WeekPlan.formatClock(minutes) }
        }
    }

    private func endPicker(_ index: Int, _ block: PlanTimeBlock) -> some View {
        PlanClockPicker(title: "Ende", value: block.end, fallback: 12 * 60) { minutes in
            if blocks.indices.contains(index) { blocks[index].end = WeekPlan.formatClock(minutes) }
        }
    }

    private func placeMenu(_ index: Int, _ block: PlanTimeBlock, id: String) -> some View {
        let name = places.first { $0.id == block.placeId }?.name
        return Menu {
            Button { if blocks.indices.contains(index) { blocks[index].placeId = nil } } label: { Text(verbatim: "Kein Ort") }
            ForEach(places.filter { !$0.archived }) { place in
                Button { if blocks.indices.contains(index) { blocks[index].placeId = place.id } } label: { Text(verbatim: place.name) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(TT.textSecondary)
                Text(verbatim: name ?? "Ort wählen").foregroundStyle(name == nil ? TT.textSecondary : TT.textPrimary)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(TT.textSecondary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel(Text(verbatim: "Ort des Blocks \(index + 1): \(name ?? "keiner")")).accessibilityIdentifier("\(id).place")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
