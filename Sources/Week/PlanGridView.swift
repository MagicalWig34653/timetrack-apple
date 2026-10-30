#if os(iOS)
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// U2: the graphical week planner, modelled on the PWA planner (P11/P13): days are columns, the time axis runs down, blocks are painted,
// moved and resized with 15-minute snapping; a tap opens the block sheet. Geometry and edits live in the core (`PlanGrid`,
// `PlanGridEdit`, `WeekPlanStore`); this file only turns touches, pointer and keys into those calls.

struct BlockRef: Identifiable, Hashable {
    var day: Int
    var index: Int
    var id: String { "\(day)#\(index)" }
}

/// What a running move gesture shows: the target day and the moved range.
private struct MovePreview: Equatable {
    var source: BlockRef
    var day: Int
    var range: MinuteRange
}

private struct ResizePreview: Equatable {
    var block: BlockRef
    var range: MinuteRange
}

private struct PaintPreview: Equatable {
    var day: Int
    var range: MinuteRange
}

/// VoiceOver custom actions of one block: edit, shift by a quarter hour, move each edge, delete.
private struct BlockAccessibility: ViewModifier {
    let store: WeekPlanStore
    let ref: BlockRef
    let block: PlanTimeBlock
    let range: MinuteRange
    let edit: () -> Void
    let nudge: (Int) -> Void
    let deselect: () -> Void

    func body(content: Content) -> some View {
        let note = (block.note ?? "").isEmpty ? "" : ", \(block.note ?? "")"
        content
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "\(block.kind.title) von \(block.start) bis \(block.end) Uhr\(note)"))
            .accessibilityHint(Text(verbatim: "Doppeltippen zum Bearbeiten"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text(verbatim: "Bearbeiten")) { edit() }
            .accessibilityAction(named: Text(verbatim: "Viertelstunde früher")) { nudge(-15) }
            .accessibilityAction(named: Text(verbatim: "Viertelstunde später")) { nudge(15) }
            .accessibilityAction(named: Text(verbatim: "Ende 15 Minuten später")) { store.resizeBlock(ref.day, at: ref.index, edge: .end, to: range.end + 15) }
            .accessibilityAction(named: Text(verbatim: "Ende 15 Minuten früher")) { store.resizeBlock(ref.day, at: ref.index, edge: .end, to: range.end - 15) }
            .accessibilityAction(named: Text(verbatim: "Beginn 15 Minuten früher")) { store.resizeBlock(ref.day, at: ref.index, edge: .start, to: range.start - 15) }
            .accessibilityAction(named: Text(verbatim: "Beginn 15 Minuten später")) { store.resizeBlock(ref.day, at: ref.index, edge: .start, to: range.start + 15) }
            .accessibilityAction(named: Text(verbatim: "Löschen")) { store.eraseBlock(ref.day, at: ref.index); deselect() }
            .accessibilityIdentifier("plan.block.\(store.drafts[safe: ref.day]?.date ?? "").\(ref.index)")
    }
}

struct PlanGridPlanner: View {
    let store: WeekPlanStore
    let places: [Place]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var windowStart = 0
    @State private var brush: PlanBlockKind = .work
    @State private var selected: BlockRef?
    @State private var sheet: BlockRef?
    @State private var copySource: Int?
    @State private var move: MovePreview?
    @State private var resize: ResizePreview?
    @State private var paint: PaintPreview?
    @State private var hover: (day: Int, minute: Int)?
    @SwiftUI.FocusState private var gridFocused: Bool

    private let gutter: CGFloat = 38

    init(store: WeekPlanStore, places: [Place]) {
        self.store = store
        self.places = places
    }

    private var wide: Bool { sizeClass == .regular }
    private var columns: Int { wide ? 7 : 3 }
    private var hourHeight: CGFloat { wide ? 56 : 52 }
    private var visible: Range<Int> {
        let start = wide ? 0 : min(max(windowStart, 0), 7 - columns)
        return start..<(start + columns)
    }

    private var hours: (start: Int, end: Int) {
        PlanGrid.visibleHours(store.drafts.flatMap { PlanGridEdit.ranges($0.blocks).map(\.range) })
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if !wide { dayStrip }
            header
            ScrollView {
                gridBody
                    .padding(.bottom, TT.Space.m)
                hints
                    .padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.l)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background { shortcuts }
        .sheet(item: $sheet) { ref in
            PlanBlockSheet(store: store, ref: ref, places: places)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: Binding(get: { copySource.map { CopySource(index: $0) } }, set: { copySource = $0?.index })) { source in
            CopyDaySheet(store: store, source: source.index)
                .presentationDetents([.medium])
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: store.drafts)
    }

    private struct CopySource: Identifiable { let index: Int; var id: Int { index } }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: TT.Space.s) {
            ScrollView(.horizontal) {
                HStack(spacing: TT.Space.xs) {
                    ForEach(PlanBlockKind.selectable, id: \.self) { kind in
                        Button { brush = kind; TTHaptics.play(.selection) } label: {
                            HStack(spacing: 5) {
                                PlanKindSwatch(kind: kind, size: 20)
                                Text(verbatim: kind.title).font(TTFont.meta).foregroundStyle(TT.textPrimary)
                            }
                            .padding(.horizontal, 8).frame(minHeight: 36)
                            .background(brush == kind ? kind.tint.opacity(0.22) : Color.clear, in: .capsule)
                            .overlay(Capsule().strokeBorder(brush == kind ? kind.tint : TT.separator, lineWidth: brush == kind ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: "Pinsel \(kind.title)"))
                        .accessibilityAddTraits(brush == kind ? .isSelected : [])
                        .accessibilityIdentifier("plan.brush.\(kind.rawValue)")
                    }
                }
                .padding(.horizontal, TT.Space.l)
            }
            .scrollIndicators(.hidden)
            Button { store.undo(); TTHaptics.play(.softTap) } label: { Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 44) }
                .disabled(!store.canUndo).accessibilityLabel(Text(verbatim: "Rückgängig")).accessibilityIdentifier("plan.undo")
            Button { store.redo(); TTHaptics.play(.softTap) } label: { Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 44) }
                .disabled(!store.canRedo).accessibilityLabel(Text(verbatim: "Wiederholen")).accessibilityIdentifier("plan.redo")
            weekMenu
                .padding(.trailing, TT.Space.s)
        }
        .buttonStyle(.borderless)
    }

    private var weekMenu: some View {
        Menu {
            Button { store.applyStandard() } label: { Label("Standardwoche", systemImage: "calendar") }
            Button { store.applySame() } label: { Label("Erster Tag für alle Werktage", systemImage: "rectangle.on.rectangle") }
            Button { Task { _ = await store.copyLastWeek() } } label: { Label("Vorwoche übernehmen", systemImage: "arrow.counterclockwise") }
            Divider()
            Button(role: .destructive) { store.applyClear() } label: { Label("Woche leeren", systemImage: "trash") }
        } label: { Image(systemName: "ellipsis.circle").imageScale(.large).frame(width: 40, height: 44) }
            .accessibilityLabel(Text(verbatim: "Wochenaktionen")).accessibilityIdentifier("plan.week_menu")
    }

    // MARK: Day strip (compact)

    private var dayStrip: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let inWindow = visible.contains(i)
                Button { windowStart = min(max(i - 1, 0), 7 - columns); TTHaptics.play(.selection) } label: {
                    VStack(spacing: 1) {
                        Text(verbatim: String(PlanFormat.weekdayHeaders[i].prefix(2))).font(TTFont.eyebrow)
                        Text(verbatim: String(LocalDays.parse(store.drafts[safe: i]?.date ?? "")?.day ?? 0)).font(.system(.callout, weight: .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(inWindow ? TT.textPrimary : TT.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(inWindow ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.window.\(i)")
            }
        }
        .padding(.horizontal, TT.Space.l)
    }

    // MARK: Header (day columns)

    private var header: some View {
        GeometryReader { proxy in
            let colW = (proxy.size.width - gutter) / CGFloat(columns)
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter)
                ForEach(Array(visible), id: \.self) { i in dayHeader(i).frame(width: colW) }
            }
        }
        .frame(height: 70)
        .padding(.top, 2)
    }

    private func dayHeader(_ i: Int) -> some View {
        let day = store.days[safe: i]
        let draft = store.drafts[safe: i]
        let planned = day.flatMap { $0.isBlocked ? 0 : draft.flatMap { WeekPlan.plannedSeconds($0) } } ?? 0
        return VStack(spacing: 2) {
            Text(verbatim: day.map { dayTitle($0.date, calendar: store.calendar) } ?? "").font(TTFont.meta.weight(.semibold)).foregroundStyle(TT.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            if let day, !day.isBlocked {
                Menu {
                    Button { store.setMode(i, nil) } label: { Text(verbatim: "Kein Plan") }
                    ForEach(PlanMode.selectable, id: \.self) { mode in Button { store.setMode(i, mode) } label: { Label(mode.plainName, systemImage: mode.symbol) } }
                    Divider()
                    Button { copySource = i } label: { Label("Tag kopieren nach …", systemImage: "doc.on.doc") }
                } label: {
                    HStack(spacing: 3) {
                        if let mode = draft?.mode, mode != .unknown { Image(systemName: mode.symbol).imageScale(.small) }
                        Text(verbatim: draft?.mode.flatMap { $0 == .unknown ? nil : $0.plainName } ?? "—").lineLimit(1)
                    }
                    .font(.system(.caption2, weight: .semibold)).foregroundStyle(draft?.mode?.tint ?? TT.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 3).background((draft?.mode?.tint ?? TT.textSecondary).opacity(0.14), in: .capsule)
                    .frame(minHeight: 30)
                }
                .accessibilityLabel(Text(verbatim: "Tagesart \(dayTitle(day.date, calendar: store.calendar))"))
                .accessibilityIdentifier("plan.mode.\(day.date)")
            } else if let blocked = day?.blockedBy {
                Text(verbatim: blocked.label).font(.system(.caption2)).foregroundStyle(TT.textSecondary).lineLimit(2).minimumScaleFactor(0.7).frame(minHeight: 30)
            }
            Text(verbatim: planned > 0 ? DurationFormat.hoursMinutes(planned) : "").font(.system(.caption2)).monospacedDigit().foregroundStyle(TT.textSecondary)
        }
        .padding(.horizontal, 1)
    }

    // MARK: Grid

    private var gridBody: some View {
        GeometryReader { proxy in
            let colW = (proxy.size.width - gutter) / CGFloat(columns)
            let h = hours
            let height = CGFloat(h.end - h.start) * hourHeight
            ZStack(alignment: .topLeading) {
                hourLines(h: h, width: proxy.size.width)
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: gutter, height: height)
                    ForEach(Array(visible), id: \.self) { i in
                        dayColumn(i, colW: colW, startHour: h.start, height: height)
                            .frame(width: colW, height: height)
                    }
                }
                if let hover, visible.contains(hover.day) {
                    hoverLine(hover, colW: colW, startHour: h.start)
                }
            }
            .frame(height: height)
        }
        .frame(height: CGFloat(hours.end - hours.start) * hourHeight)
        .focusable()
        .focused($gridFocused)
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .delete, .deleteForward, .return, .escape]) { press in handleKey(press) }
    }

    private func hourLines(h: (start: Int, end: Int), width: CGFloat) -> some View {
        Canvas { context, size in
            for hour in h.start...h.end {
                let y = CGFloat(hour - h.start) * hourHeight
                var line = Path()
                line.move(to: CGPoint(x: gutter, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.gray.opacity(0.28)), lineWidth: 0.5)
                if hour < h.end {
                    let half = Path { $0.move(to: CGPoint(x: gutter, y: y + hourHeight / 2)); $0.addLine(to: CGPoint(x: size.width, y: y + hourHeight / 2)) }
                    context.stroke(half, with: .color(.gray.opacity(0.12)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
                context.draw(Text(verbatim: String(format: "%02d", hour)).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: gutter - 6, y: y + 8), anchor: .trailing)
            }
        }
        .frame(width: width, height: CGFloat(h.end - h.start) * hourHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hoverLine(_ hover: (day: Int, minute: Int), colW: CGFloat, startHour: Int) -> some View {
        let y = CGFloat(PlanGrid.y(forMinutes: hover.minute, startHour: startHour, hourHeight: Double(hourHeight)))
        let x = gutter + CGFloat(hover.day - visible.lowerBound) * colW
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.accentColor.opacity(0.7)).frame(width: colW, height: 1)
            Text(verbatim: WeekPlan.formatClock(hover.minute)).font(.caption2.monospacedDigit()).padding(.horizontal, 4)
                .background(Color.accentColor, in: .capsule).foregroundStyle(.white).offset(x: 2, y: -16)
        }
        .offset(x: x, y: y).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func dayColumn(_ i: Int, colW: CGFloat, startHour: Int, height: CGFloat) -> some View {
        let draft = store.drafts[safe: i]
        let blocked = store.days[safe: i]?.isBlocked ?? true
        let hh = Double(hourHeight)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(blocked ? TT.separator.opacity(0.35) : Color.clear)
                .overlay { if blocked { PlanPatternOverlay(pattern: .stripes).opacity(0.25) } }
                .overlay(alignment: .leading) { Rectangle().fill(TT.separator.opacity(0.5)).frame(width: 0.5) }
                .contentShape(.rect)
                .gesture(paintGesture(i, startHour: startHour), isEnabled: !blocked)
                .onTapGesture { location in if !blocked { tapEmpty(i, y: location.y, startHour: startHour) } }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): if !blocked { hover = (i, PlanGrid.minutes(atY: point.y, startHour: startHour, hourHeight: hh)) }
                    case .ended: hover = nil
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: columnLabel(i)))
                .accessibilityAction(named: Text(verbatim: "Block hinzufügen")) { if !blocked { addDefaultBlock(i) } }
                .accessibilityAction(named: Text(verbatim: "Tag kopieren")) { if !blocked { copySource = i } }
                .accessibilityIdentifier("plan.col.\(draft?.date ?? "\(i)")")
            if let draft, !blocked {
                ForEach(Array(draft.blocks.enumerated()), id: \.offset) { index, block in
                    if let range = PlanGridEdit.ranges(draft.blocks).first(where: { $0.index == index })?.range {
                        blockView(BlockRef(day: i, index: index), block: block, range: range, colW: colW, startHour: startHour)
                    }
                }
            }
            if let paint, paint.day == i {
                ghost(range: paint.range, kind: brush, colW: colW, startHour: startHour, dashed: true)
            }
            if let move, move.day == i {
                ghost(range: move.range, kind: draft?.blocks[safe: move.source.index]?.kind ?? brush, colW: colW, startHour: startHour, dashed: false)
            }
        }
        .coordinateSpace(.named("grid-\(i)"))
    }

    private func ghost(range: MinuteRange, kind: PlanBlockKind, colW: CGFloat, startHour: Int, dashed: Bool) -> some View {
        let y = CGFloat(PlanGrid.y(forMinutes: range.start, startHour: startHour, hourHeight: Double(hourHeight)))
        let height = CGFloat(range.duration) / 60 * hourHeight
        return RoundedRectangle(cornerRadius: 8, style: .continuous).fill(kind.tint.opacity(0.35))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(kind.tint, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 3] : [])))
            .overlay(alignment: .topLeading) {
                Text(verbatim: "\(WeekPlan.formatClock(range.start))–\(WeekPlan.formatClock(range.end))").font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(TT.textPrimary).padding(3)
            }
            .frame(width: colW - 4, height: height).offset(x: 2, y: y).allowsHitTesting(false)
    }

    private func columnLabel(_ i: Int) -> String {
        guard let day = store.days[safe: i], let draft = store.drafts[safe: i] else { return "" }
        let title = MonthCellLabel.longDay(day.date)
        if let blocked = day.blockedBy { return "\(title), \(blocked.label), gesperrt" }
        let planned = WeekPlan.plannedSeconds(draft).map { "geplant \(DurationFormat.hoursMinutes($0))" } ?? "kein Plan"
        return "\(title), \(draft.mode?.plainName ?? "frei"), \(planned), \(draft.blocks.count) Blöcke"
    }

    // MARK: Block

    private func blockView(_ ref: BlockRef, block: PlanTimeBlock, range: MinuteRange, colW: CGFloat, startHour: Int) -> some View {
        let shown = resize?.block == ref ? (resize?.range ?? range) : range
        let y = CGFloat(PlanGrid.y(forMinutes: shown.start, startHour: startHour, hourHeight: Double(hourHeight)))
        let height = max(18, CGFloat(shown.duration) / 60 * hourHeight)
        let visual = blockVisual(ref, block: block, range: range, colW: colW, height: height, startHour: startHour)
        return visual
            .frame(width: colW - 4, height: height)
            .opacity(move?.source == ref ? 0.35 : 1)
            .offset(x: 2, y: y)
            .contentShape(.rect)
            .onTapGesture { selected = ref; gridFocused = true; sheet = ref; TTHaptics.play(.selection) }
            .gesture(moveGesture(ref, range: range, colW: colW))
            .hoverEffect(.highlight)
            .modifier(BlockAccessibility(store: store, ref: ref, block: block, range: range,
                                         edit: { sheet = ref }, nudge: { nudge(ref, by: $0) }, deselect: { selected = nil }))
    }

    private func blockVisual(_ ref: BlockRef, block: PlanTimeBlock, range: MinuteRange, colW: CGFloat, height: CGFloat, startHour: Int) -> some View {
        let isSelected = selected == ref
        let kind = block.kind
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let showHandles = isSelected || wide
        return ZStack(alignment: .topLeading) {
            shape.fill(kind.tint)
                .overlay(PlanPatternOverlay(pattern: kind.pattern).clipShape(shape))
                .overlay(shape.strokeBorder(isSelected ? TT.textPrimary : Color.white.opacity(0.35), lineWidth: isSelected ? 2.5 : 1))
            blockText(block, height: height, colW: colW)
            if showHandles { resizeHandle(ref, range: range, edge: .start, colW: colW, startHour: startHour).frame(maxHeight: .infinity, alignment: .top) }
            if showHandles { resizeHandle(ref, range: range, edge: .end, colW: colW, startHour: startHour).frame(maxHeight: .infinity, alignment: .bottom) }
        }
    }

    private func blockText(_ block: PlanTimeBlock, height: CGFloat, colW: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: block.kind.symbol).font(.system(size: 10, weight: .bold))
                if height >= 30 && colW > 70 { Text(verbatim: block.kind.title).font(.system(size: 11, weight: .semibold)).lineLimit(1) }
            }
            if height >= 46 { Text(verbatim: "\(block.start)–\(block.end)").font(.system(size: 10).monospacedDigit()).lineLimit(1) }
            if height >= 62, let note = block.note, !note.isEmpty { Text(verbatim: note).font(.system(size: 10)).lineLimit(2).opacity(0.9) }
        }
        .foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 1).padding(4)
    }

    private func resizeHandle(_ ref: BlockRef, range: MinuteRange, edge: PlanGrid.Edge, colW: CGFloat, startHour: Int) -> some View {
        let hh = Double(hourHeight)
        return Capsule().fill(Color.white.opacity(0.9)).frame(width: 26, height: 4)
            .shadow(color: .black.opacity(0.4), radius: 1)
            .frame(width: colW - 4, height: 22)
            .contentShape(.rect)
            .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("grid-\(ref.day)")).onChanged { value in
                let minute = PlanGrid.minutes(atY: value.location.y, startHour: startHour, hourHeight: hh)
                let bounds = PlanGridEdit.neighbourBounds(store.drafts[safe: ref.day]?.blocks ?? [], at: ref.index)
                resize = ResizePreview(block: ref, range: PlanGrid.resize(range, edge: edge, to: minute, bounds: bounds))
            }.onEnded { value in
                let minute = PlanGrid.minutes(atY: value.location.y, startHour: startHour, hourHeight: hh)
                store.resizeBlock(ref.day, at: ref.index, edge: edge, to: minute)
                resize = nil
                TTHaptics.play(.softTap)
            })
            .accessibilityHidden(true)
    }

    // MARK: Gestures

    private func paintGesture(_ i: Int, startHour: Int) -> some Gesture {
        let hh = Double(hourHeight)
        return LongPressGesture(minimumDuration: 0.22).sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                let anchor = PlanGrid.minutes(atY: drag.startLocation.y, startHour: startHour, hourHeight: hh)
                let current = PlanGrid.minutes(atY: drag.location.y, startHour: startHour, hourHeight: hh)
                let range = PlanGrid.paintRange(anchor: anchor, current: current)
                if paint?.range != range { TTHaptics.play(.selection) }
                paint = PaintPreview(day: i, range: range)
            }
            .onEnded { value in
                defer { paint = nil }
                guard case .second(true, let drag) = value else { return }
                let range: MinuteRange
                if let drag {
                    let anchor = PlanGrid.minutes(atY: drag.startLocation.y, startHour: startHour, hourHeight: hh)
                    range = PlanGrid.paintRange(anchor: anchor, current: PlanGrid.minutes(atY: drag.location.y, startHour: startHour, hourHeight: hh))
                } else if let preview = paint { range = preview.range } else { return }
                commitPaint(i, range)
            }
    }

    private func tapEmpty(_ i: Int, y: CGFloat, startHour: Int) {
        let start = PlanGrid.minutes(atY: Double(y), startHour: startHour, hourHeight: Double(hourHeight))
        commitPaint(i, MinuteRange(start: start, end: min(start + 60, PlanGrid.lastMinute)))
    }

    private func commitPaint(_ i: Int, _ range: MinuteRange) {
        if let index = store.paintBlock(i, range: range, kind: brush) {
            selected = BlockRef(day: i, index: index)
            TTHaptics.play(.softTap)
        } else {
            TTHaptics.play(.warning)
        }
    }

    private func addDefaultBlock(_ i: Int) {
        let draft = store.drafts[safe: i]
        let start = draft?.blocks.last?.endMinutes ?? 8 * 60
        commitPaint(i, MinuteRange(start: min(start, PlanGrid.lastMinute - 60), end: min(start + 60, PlanGrid.lastMinute)))
    }

    private func moveGesture(_ ref: BlockRef, range: MinuteRange, colW: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                let delta = Int(drag.translation.height / hourHeight * 60)
                let dayShift = Int((drag.translation.width / colW).rounded())
                let target = min(max(ref.day + dayShift, visible.lowerBound), visible.upperBound - 1)
                let moved = PlanGrid.move(range, by: delta)
                if move?.range != moved || move?.day != target { TTHaptics.play(.selection) }
                move = MovePreview(source: ref, day: target, range: moved)
                selected = ref
            }
            .onEnded { value in
                defer { move = nil }
                guard case .second(true, let drag?) = value else { return }
                let delta = Int(drag.translation.height / hourHeight * 60)
                let dayShift = Int((drag.translation.width / colW).rounded())
                let target = min(max(ref.day + dayShift, visible.lowerBound), visible.upperBound - 1)
                if let index = store.moveBlock(from: ref.day, at: ref.index, toDay: target, range: PlanGrid.move(range, by: delta)) {
                    selected = BlockRef(day: target, index: index)
                    TTHaptics.play(.softTap)
                }
            }
    }

    private func nudge(_ ref: BlockRef, by minutes: Int) {
        guard let range = store.drafts[safe: ref.day].flatMap({ PlanGridEdit.ranges($0.blocks).first { $0.index == ref.index }?.range }) else { return }
        if let index = store.moveBlock(from: ref.day, at: ref.index, toDay: ref.day, range: PlanGrid.move(range, by: minutes, step: 1)) { selected = BlockRef(day: ref.day, index: index) }
    }

    // MARK: Keyboard (iPad)

    @ViewBuilder private var shortcuts: some View {
        HStack {
            Button("") { store.undo() }.keyboardShortcut("z", modifiers: .command)
            Button("") { store.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard let ref = selected, let range = store.drafts[safe: ref.day].flatMap({ PlanGridEdit.ranges($0.blocks).first { $0.index == ref.index }?.range }) else { return .ignored }
        let step = press.modifiers.contains(.shift) ? PlanGrid.fineMinutes : PlanGrid.snapMinutes
        switch press.key {
        case .upArrow, .downArrow:
            let delta = press.key == .upArrow ? -step : step
            if press.modifiers.contains(.option) {
                store.resizeBlock(ref.day, at: ref.index, edge: .end, to: range.end + delta, step: step)
            } else {
                nudge(ref, by: delta)
            }
            return .handled
        case .leftArrow, .rightArrow:
            let target = ref.day + (press.key == .leftArrow ? -1 : 1)
            guard visible.contains(target), let index = store.moveBlock(from: ref.day, at: ref.index, toDay: target, range: range) else { return .handled }
            selected = BlockRef(day: target, index: index)
            return .handled
        case .delete, .deleteForward:
            store.eraseBlock(ref.day, at: ref.index)
            selected = nil
            return .handled
        case .return:
            sheet = ref
            return .handled
        case .escape:
            selected = nil
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: Hints

    @ViewBuilder private var hints: some View {
        let entries = (0..<7).compactMap { i -> (String, [PlanHint])? in
            let list = store.hints(at: i)
            guard !list.isEmpty, let day = store.days[safe: i] else { return nil }
            return (dayTitle(day.date, calendar: store.calendar), list)
        }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: TT.Space.xs) {
                ForEach(entries, id: \.0) { title, list in PlanHintsView(hints: list, dayTitle: title) }
            }
            .padding(.top, TT.Space.s)
        }
    }
}
#endif
