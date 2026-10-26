import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

#if os(macOS)
/// The Mac "Kalender" screen (on iOS/iPadOS the calendar is the month zoom of the "Zeit" screen, Z2): month grid with holidays, absences and plan; day detail as sheet (iPhone) or right-hand panel (iPad/Mac).
struct CalendarScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let store = model.calendar {
                CalendarContent(store: store)
            } else {
                ScrollView { EmptyState(symbol: "calendar", title: "vacation.disabled").padding(TT.Space.l) }.ttScreenBackground()
            }
        }
        .navigationTitle(Text(verbatim: ""))
    }
}

private struct CalendarContent: View {
    let store: CalendarStore
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var absenceRequest: AbsenceRequest?
    @State private var sheet: PlanSheet?
    @State private var picker = false
    @State private var pagingEdge: Edge = .trailing

    private var wide: Bool { planningIsWide(sizeClass) }
    private var actions: AbsenceEditorActions { AbsenceEditorActions(calendar: store) }
    private var focusDay: LocalDay { store.selectedDay ?? store.today }

    /// Z1: modelled on the Apple Calendar month view. The grid stays put, the details of the selected day sit below (iPhone) or beside it (iPad).
    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await store.load() } }.accessibilityIdentifier("calendar.error").padding(.horizontal, TT.Space.l) }
            if store.isRangeMode { rangeBar.padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.s) }
            if wide {
                HStack(alignment: .top, spacing: TT.Space.xl) {
                    VStack(alignment: .leading, spacing: TT.Space.m) { header; pagedGrid; Legend(); Spacer(minLength: 0) }
                        .frame(maxWidth: 640)
                    detailScroll.frame(maxWidth: .infinity)
                }
                .padding(.horizontal, TT.Space.l)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: TT.Space.s) { header; pagedGrid }
                    .padding(.horizontal, TT.Space.l)
                detailScroll
            }
        }
        .ttScreenBackground()
        .task {
            await store.load()
            if store.selectedDay == nil { await store.select(store.today) }
        }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await store.load() } } }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { TTHaptics.play(.softTap); pagingEdge = store.firstOfMonth < store.today ? .trailing : .leading; Task { await store.goToToday(); await store.select(store.today) } } label: { Text("calendar.today") }.accessibilityIdentifier("calendar.today")
                Menu {
                    Button { store.beginRange(at: focusDay) } label: { Label("plan.action.range", systemImage: "calendar.day.timeline.leading") }
                } label: { Label("plan.add", systemImage: "plus") }
                    .accessibilityIdentifier("calendar.add")
            }
        }
        .absenceEditor($absenceRequest, actions: actions)
        .sheet(item: $sheet) { sheet in PlanSheetHost(sheet: sheet, store: store) }
    }

    /// Details of the selected day. The list scrolls, the month grid above does not (like Apple Calendar).
    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                DayDetail(store: store, day: focusDay, absenceRequest: $absenceRequest, sheet: $sheet)
                if !wide { Legend() }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .frame(maxWidth: wide ? .infinity : TT.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.load(); await store.loadDetail() }
    }

    /// The grid with a push transition between months and a horizontal swipe, as in Apple Calendar.
    private var pagedGrid: some View {
        MonthGrid(store: store, onTap: tap, onLongPress: longPress)
            .id(store.firstOfMonth)
            .transition(.push(from: pagingEdge))
            .animation(.smooth(duration: 0.3), value: store.firstOfMonth)
            .clipped()
            .contentShape(.rect)
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                shift(value.translation.width < 0 ? 1 : -1)
            })
    }

    private func shift(_ count: Int) {
        TTHaptics.play(.softTap)
        pagingEdge = count > 0 ? .trailing : .leading
        Task {
            await store.shiftMonths(count)
            await selectDefault()
        }
    }

    /// After a month change the selection moves into the new month: today when visible, otherwise the 1st.
    private func selectDefault() async {
        guard !store.isRangeMode else { return }
        await store.select(store.isInVisibleMonth(store.today) ? store.today : store.firstOfMonth)
    }

    private var header: some View {
        HStack(spacing: TT.Space.s) {
            Button { picker = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: PlanFormat.monthName(store.month, calendar: store.calendar)).font(.system(.largeTitle, design: .default, weight: .bold)).foregroundStyle(TT.textPrimary)
                    Text(verbatim: String(store.year)).font(.system(.title2, weight: .regular)).foregroundStyle(Color.accentColor)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
            }
            .accessibilityLabel(Text(verbatim: PlanFormat.monthTitle(year: store.year, month: store.month, calendar: store.calendar)))
            .accessibilityIdentifier("calendar.title")
            .accessibilityHint(Text("calendar.picker.hint"))
            .popover(isPresented: $picker) { MonthPicker(store: store) { picker = false; Task { await selectDefault() } }.presentationCompactAdaptation(.popover) }
            Spacer(minLength: TT.Space.s)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(Text("calendar.previous_month")).accessibilityIdentifier("calendar.prev")
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(Text("calendar.next_month")).accessibilityIdentifier("calendar.next")
                }
            }
        }
        .buttonStyle(.borderless)
    }

    private var rangeBar: some View {
        Card(padding: TT.Space.m) {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                if let range = store.chosenRange {
                    Text("calendar.range.chosen \(PlanFormat.range(range.start, range.end, calendar: store.calendar))").font(TTFont.label)
                } else {
                    Text("calendar.range.hint").font(TTFont.label)
                }
                HStack {
                    ForEach([AbsenceKind.vacation, .sick], id: \.self) { kind in
                        Button { startRange(kind) } label: { Label(kind.shortKey, systemImage: kind.ttSymbol).lineLimit(1).minimumScaleFactor(0.8) }
                            .buttonStyle(.ttSecondary).disabled(store.chosenRange == nil).accessibilityIdentifier("range.\(kind.rawValue)")
                    }
                    Spacer()
                    Button("common.cancel") { store.cancelRange() }.buttonStyle(.borderless).accessibilityIdentifier("range.cancel")
                }
            }
        }
    }

    private func startRange(_ kind: AbsenceKind) {
        guard let range = store.chosenRange else { return }
        store.cancelRange()
        absenceRequest = AbsenceRequest(kind: kind, start: range.start, end: range.end)
    }

    private func tap(_ day: LocalDay) {
        if store.isRangeMode {
            // First tap (or a restart) marks the start, the second completes the range.
            let completes = store.rangeStart != nil && store.rangeEnd == nil
            TTHaptics.play(completes ? .success : .tap)
            store.tapInRangeMode(day)
            return
        }
        TTHaptics.play(.selection)
        Task { await store.select(day) }
        if !store.isInVisibleMonth(day), let p = LocalDays.parse(day) { Task { await store.goTo(year: p.year, month: p.month) } }
    }

    private func longPress(_ day: LocalDay) {
        TTHaptics.play(.tap)
        store.beginRange(at: day)
    }
}

#endif

struct MonthPicker: View {
    let store: CalendarStore
    let done: () -> Void
    @State private var year = 0

    var body: some View {
        VStack(spacing: TT.Space.s) {
            HStack {
                Button { year -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel(Text("vacation.previous_year"))
                Spacer()
                Text(verbatim: String(year)).font(TTFont.cardTitle).monospacedDigit()
                Spacer()
                Button { year += 1 } label: { Image(systemName: "chevron.right") }.accessibilityLabel(Text("vacation.next_year"))
            }
            .buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: TT.Space.s) {
                ForEach(1...12, id: \.self) { month in
                    Button { TTHaptics.play(.selection); Task { await store.goTo(year: year, month: month) }; done() } label: {
                        Text(verbatim: String(PlanFormat.monthName(month, calendar: store.calendar).prefix(3))).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered).tint(month == store.month && year == store.year ? nil : TT.textSecondary)
                }
            }
        }
        .padding(TT.Space.l).frame(minWidth: 260)
        .onAppear { year = store.year }
    }
}

struct Legend: View {
    var body: some View {
        let items: [(String, Color, LocalizedStringKey)] = [
            ("beach.umbrella.fill", TT.kindVacation, "absence.vacation"), ("cross.case.fill", TT.kindSick, "absence.sick"),
            ("checkmark.seal.fill", TT.kindExcused, "absence.excused"), ("calendar.badge.clock", TT.kindOther, "absence.other"),
            ("party.popper.fill", TT.kindHoliday, "mark.holiday"),
        ]
        HStack(spacing: TT.Space.m) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    Image(systemName: items[index].0).foregroundStyle(items[index].1).imageScale(.small)
                    Text(items[index].2).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                }
            }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine).accessibilityLabel(Text("calendar.legend"))
    }
}

#if os(macOS)
// MARK: - Grid

private struct MonthGrid: View {
    let store: CalendarStore
    let onTap: (LocalDay) -> Void
    let onLongPress: (LocalDay) -> Void

    var body: some View {
        let days = store.gridDays
        let rows = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("calendar.week_short").frame(width: 26).accessibilityHidden(true)
                ForEach(PlanFormat.weekdayHeaders, id: \.self) { Text(verbatim: String($0.prefix(2))).frame(maxWidth: .infinity) }
            }
            .font(TTFont.eyebrow).foregroundStyle(TT.textTertiary)
            .padding(.bottom, TT.Space.xs)
            ForEach(rows, id: \.first) { week in
                Divider().overlay(TT.textTertiary.opacity(0.25))
                HStack(spacing: 0) {
                    Text(verbatim: week.first.flatMap { LocalDays.isoWeek(of: $0) }.map(String.init) ?? "")
                        .font(.caption2).foregroundStyle(TT.textTertiary).frame(width: 26)
                        .accessibilityLabel(Text("calendar.week_label \(week.first.flatMap { LocalDays.isoWeek(of: $0) } ?? 0)"))
                    ForEach(week, id: \.self) { day in
                        DayCell(store: store, day: day)
                            .onTapGesture { onTap(day) }
                            .onLongPressGesture(minimumDuration: 0.45) { onLongPress(day) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("day.\(day)")
                            .accessibilityAction(named: Text("plan.action.range")) { onLongPress(day) }
                    }
                }
            }
        }
    }
}

/// One day of the grid: number (today = accent circle, selection = dark circle) and up to three dots, no cell fills.
private struct DayCell: View {
    let store: CalendarStore
    let day: LocalDay
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let info = store.info(for: day)
        let inMonth = store.isInVisibleMonth(day)
        let isToday = day == store.today
        let selected = day == store.selectedDay && !store.isRangeMode
        let inRange = store.isInRange(day)
        let weekend = (LocalDays.isoWeekday(day) ?? 1) >= 6
        VStack(spacing: 3) {
            number(isToday: isToday, selected: selected, inMonth: inMonth, weekend: weekend, holiday: info.isHoliday)
            HStack(spacing: 3) {
                ForEach(Array(markers(info).enumerated()), id: \.offset) { _, tint in Circle().fill(tint).frame(width: 6, height: 6) }
            }
            .frame(height: 7)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: sizeClass == .regular ? 92 : 52)
        .background(inRange ? Color.accentColor.opacity(0.22) : .clear, in: .rect(cornerRadius: 10))
        .opacity(inMonth ? 1 : 0.5)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label(info)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func number(isToday: Bool, selected: Bool, inMonth: Bool, weekend: Bool, holiday: Bool) -> some View {
        let text = Text(verbatim: String(LocalDays.parse(day)?.day ?? 0))
            .font(.system(.title3, design: .default, weight: isToday || selected ? .semibold : .regular)).monospacedDigit()
            .frame(width: 36, height: 36)
        if isToday {
            text.foregroundStyle(Color.white).glassEffect(.regular.tint(Color.accentColor), in: .circle)
        } else if selected {
            text.foregroundStyle(scheme == .dark ? Color.black : Color.white).background(TT.textPrimary, in: .circle)
        } else {
            text.foregroundStyle(holiday ? TT.kindHoliday : (inMonth ? (weekend ? TT.textSecondary : TT.textPrimary) : TT.textTertiary))
        }
    }

    private func markers(_ info: CalendarDayInfo) -> [Color] {
        var list: [Color] = info.absences.prefix(2).map { $0.kind.ttTint }
        if info.isHoliday { list.append(TT.kindHoliday) }
        if let plan = info.plan { list.append(plan.mode.tint) }
        return Array(list.prefix(3))
    }

    private func label(_ info: CalendarDayInfo) -> String {
        var parts = [PlanFormat.longDay(day, calendar: store.calendar)]
        if day == store.today { parts.append(String(localized: "time.today")) }
        parts += info.holidays.map(\.name)
        parts += info.schoolHolidays.map(\.name)
        parts += info.absences.map { "\($0.kind.plainName), \($0.status.plainName)" }
        if let plan = info.plan { parts.append(String(localized: "calendar.plan_label \(plan.mode.plainName)")) }
        return parts.joined(separator: ", ")
    }
}
#endif
