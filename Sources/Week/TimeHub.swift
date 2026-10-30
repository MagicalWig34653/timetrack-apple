#if os(iOS)
import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

// Z2: the one "Zeit" screen (iOS/iPadOS). Strings of this file live in their own table `Z2.xcstrings`.

enum Z2 {
    static func s(_ key: String.LocalizationValue) -> String { String(localized: key, table: "Z2") }
    static func t(_ key: LocalizedStringKey) -> Text { Text(key, tableName: "Z2") }
}

/// One anchor day, two zoom levels. Month: the grid with the selected day's details (recorded entries, plan, absence, device events).
/// Week: summary, days with their entries; the week planner is the editing mode of this zoom, not a screen of its own.
/// Each figure exists once per zoom level: the day detail in the month zoom is the same information as one day section of the week zoom.
struct TimeHub: View {
    let timeList: TimeListStore
    let calendar: CalendarStore?

    @Environment(AppModel.self) private var model
    @Environment(\.deviceCalendar) private var deviceCalendar
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("time.zoom") private var storedZoom = TimeZoom.month.rawValue

    @State private var focus: TimeFocus
    /// U2: the vertical month list: scroll position, month under the header and the day whose detail sheet is open.
    @State private var monthScroll = ScrollPosition(edge: .top)
    @State private var visibleMonth: MonthKey
    @State private var monthSheetDay: LocalDay?
    /// False until the list has jumped to its initial month; the scroll callbacks of the first layout pass must not overwrite it.
    @State private var monthPositioned = false
    @State private var editor: EditorRequest?
    @State private var voiding: Segment?
    @State private var touchedDay: LocalDay?
    @State private var absenceRequest: AbsenceRequest?
    @State private var sheet: PlanSheet?
    @State private var picker = false
    @State private var planningArea = false
    @State private var reportsWeek: ReportWeekRef?
    @State private var pendingNavigation: PendingNavigation?
    /// U2: week index (relative to the current week) of the paging week view.
    @State private var weekPage: Int?
    @Namespace private var selectionSpace

    struct PendingNavigation: Identifiable {
        let id = UUID()
        let action: () -> Void
    }

    init(timeList: TimeListStore, calendar: CalendarStore?) {
        self.timeList = timeList
        self.calendar = calendar
        let stored = UserDefaults.standard.string(forKey: "time.zoom").flatMap(TimeZoom.init) ?? .month
        let zoom: TimeZoom = calendar == nil ? .week : stored
        let today = timeList.calendar.day(for: .now)
        _focus = State(initialValue: TimeFocus(zoom: zoom, day: today))
        _weekPage = State(initialValue: 0)
        _visibleMonth = State(initialValue: MonthKey(day: today) ?? MonthKey(year: 2026, month: 1))
    }

    // MARK: - Derived

    private var wide: Bool { sizeClass == .regular }
    private var animation: Animation { Z2Motion.spring(reduceMotion: reduceMotion) }
    private var planEnabled: Bool { model.isEnabled(.planning) && model.apiClient != nil }
    private var reportsEnabled: Bool { model.isEnabled(.reports) && model.apiClient != nil }
    private var zoom: TimeZoom { calendar == nil ? .week : focus.zoom }
    private var today: LocalDay { timeList.calendar.day(for: .now) }
    private var weekStore: WeekStore? { model.apiClient.map { WeekStoreCache.shared.weekStore($0, calendar: model.dayCalendar) } }
    private var planStore: WeekPlanStore? {
        guard planEnabled, let client = model.apiClient else { return nil }
        return WeekStoreCache.shared.planStore(client, calendar: model.dayCalendar)
    }
    private var isPlanning: Bool { zoom == .week && focus.isPlanning && planStore != nil }
    private var rowHeight: CGFloat { wide ? 112 : 84 }
    private var monthLayout: MonthListLayout {
        let current = MonthKey(day: today) ?? visibleMonth
        return MonthListLayout(first: current.adding(-36), count: 73, rowHeight: rowHeight, headerHeight: 44)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ZoomHeader(title: headerTitle, subtitle: headerSubtitle, opensPicker: zoom == .month, picker: $picker, previous: { step(-1) }, next: { step(1) },
                       pickerContent: { calendar.map { store in MonthPicker(store: store) { picker = false; jump(to: store.visibleKey) } } })
                .padding(.horizontal, TT.Space.l)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            if let calendar, zoom == .month, calendar.isRangeMode { rangeBar(calendar).padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s) }
            content
        }
        .background { weekKeyboardShortcuts }
        .ttScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $editor, onDismiss: refreshAfterEdit) { request in
            SegmentEditor(store: timeList, segment: request.segment, day: request.day)
                .presentationDetents([.fraction(0.75), .large])
        }
        .sheet(item: $voiding, onDismiss: refreshAfterEdit) { segment in VoidSheet(store: timeList, segment: segment) }
        .environment(\.openPlanWeek) { monday in
            planningArea = false
            planStoreOpen(monday)
        }
        .navigationDestination(item: $reportsWeek) { week in ReportsScreen(week: week) }
        .navigationDestination(isPresented: $planningArea) {
            // Pushed screens do not inherit the environment of this view, so the hand-over is attached to the destination itself.
            PlanningHubScreen().environment(\.openPlanWeek) { monday in
                planningArea = false
                // Let the pop of the planning area finish first; switching the zoom in the same transaction left the planner blank.
                Task { try? await Task.sleep(for: .milliseconds(450)); planStoreOpen(monday) }
            }
        }
        .modifier(DaySheet(hub: self))
        .modifier(CalendarSheets(calendar: calendar, absenceRequest: $absenceRequest, sheet: $sheet))
        .alert(W.s("leave.title"), isPresented: Binding(get: { pendingNavigation != nil }, set: { if !$0 { pendingNavigation = nil } })) {
            Button(W.s("leave.discard"), role: .destructive) {
                planStore?.discard()
                let action = pendingNavigation?.action
                pendingNavigation = nil
                action?()
            }
            Button(W.s("leave.keep"), role: .cancel) { pendingNavigation = nil }
        } message: { W.t("leave.message") }
        .task(id: zoom) { await load() }
        .onChange(of: focus) { syncStores() }
        .onChange(of: focus.weekStart) { if weekPage != focusWeekIndex { weekPage = focusWeekIndex } }
        .onChange(of: monthSheetDay) { daySheetOpened() }
        .onChange(of: sheet?.id) { _, new in if new != nil { monthSheetDay = nil } }
        .onChange(of: absenceRequest?.id) { _, new in if new != nil { monthSheetDay = nil } }
                .onChange(of: scenePhase) { if scenePhase == .active { Task { await reloadAll() } } }
        .onAppear { planStore?.onSaved = {
            Task { await weekStore?.load(); await timeList.load() }
            // AUD3: write the saved plan back to the device calendar without waiting for the next foreground.
            if let deviceCalendar { CalendarAutoSync.shared.request(model: model, deviceCalendar: deviceCalendar) }
        } }
    }

    // MARK: - Header and toolbar

    private var headerTitle: String {
        switch zoom {
        case .month: PlanFormat.monthName(visibleMonth.month, calendar: timeList.calendar)
        case .week: W.s("nav.kw", LocalDays.isoWeek(of: focus.weekStart) ?? 0)
        }
    }

    private var headerSubtitle: String {
        switch zoom {
        case .month: String(visibleMonth.year)
        case .week: weekRangeText(start: focus.weekStart, end: focus.weekEnd, calendar: timeList.calendar)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if calendar != nil {
            ToolbarItem(placement: .principal) {
                Picker(Z2.s("zoom.label"), selection: Binding(get: { zoom }, set: { setZoom($0) })) {
                    Text(Z2.s("zoom.month")).tag(TimeZoom.month)
                    Text(Z2.s("zoom.week")).tag(TimeZoom.week)
                }
                .pickerStyle(.segmented).frame(width: 150)
                .accessibilityIdentifier("time.zoom")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { goToToday() } label: { Text("calendar.today") }.accessibilityIdentifier("time.today")
            if planEnabled || reportsEnabled || (calendar != nil && zoom == .month) {
                Menu {
                    if let calendar, zoom == .month {
                        Button { calendar.beginRange(at: focus.day) } label: { Label("plan.action.range", systemImage: "calendar.day.timeline.leading") }
                            .accessibilityIdentifier("calendar.range")
                    }
                    if reportsEnabled {
                        Button { reportsWeek = ReportWeekRef(containing: focus.zoom == .week ? focus.weekStart : focus.day) } label: { Label(BH.s("entry.link"), systemImage: "book.closed") }
                            .accessibilityIdentifier("time.reports")
                    }
                    if planEnabled {
                        Button { planningArea = true } label: { Label(PA.s("hub.title"), systemImage: "calendar.badge.clock") }
                            .accessibilityIdentifier("time.planning_area")
                    }
                } label: { Label(Z2.s("more.label"), systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("time.more")
            }
            Button { editor = EditorRequest(segment: nil, day: focus.day); touchedDay = focus.day } label: { Label("command.new_entry", systemImage: "plus") }
                .accessibilityIdentifier("time.new")
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch zoom {
        case .month:
            if let calendar { monthContent(calendar).transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top))) }
        case .week:
            weekContent.transition(.opacity.combined(with: .scale(scale: 1.02, anchor: .top)))
        }
    }

    private func monthContent(_ calendar: CalendarStore) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("calendar.week_short").frame(width: 26).accessibilityHidden(true)
                ForEach(PlanFormat.weekdayHeaders, id: \.self) { Text(verbatim: String($0.prefix(2))).frame(maxWidth: .infinity) }
            }
            .font(TTFont.eyebrow).foregroundStyle(TT.textTertiary).padding(.vertical, TT.Space.xs).padding(.horizontal, TT.Space.s)
            MonthList(store: calendar, layout: monthLayout, position: $monthScroll, selected: focus.day,
                      onVisibleMonth: { key in if monthPositioned, key != visibleMonth { visibleMonth = key; monthVisibleChanged(key) } },
                      onTap: { tap($0, in: calendar) }, onLongPress: { calendar.beginRange(at: $0); TTHaptics.play(.tap) })
                .padding(.horizontal, TT.Space.s)
                .frame(maxWidth: wide ? 1100 : .infinity).frame(maxWidth: .infinity)
                .overlay(alignment: .bottomTrailing) { jumpToToday }
        }
        .task {
            monthPositioned = false
            jumpMonth(to: visibleMonth, animated: false)
            try? await Task.sleep(for: .milliseconds(250))
            monthPositioned = true
        }
    }

    /// Floating "Heute" button, shown only when today's month is not the one on screen.
    @ViewBuilder private var jumpToToday: some View {
        if visibleMonth != MonthKey(day: today) {
            Button { goToToday() } label: { Label("Heute", systemImage: "arrow.uturn.backward").font(TTFont.label).padding(.horizontal, TT.Space.m).frame(minHeight: 44) }
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(TT.Space.l).padding(.bottom, 56)
                .accessibilityIdentifier("month.jump_today")
        }
    }

    private func jumpMonth(to key: MonthKey, animated: Bool) {
        let layout = monthLayout
        let y = layout.offset(of: layout.contains(key) ? key : (MonthKey(day: today) ?? key))
        if animated && !reduceMotion { withAnimation(.smooth(duration: 0.45)) { monthScroll.scrollTo(y: y) } } else { monthScroll.scrollTo(y: y) }
    }

    /// The day detail sheet of both zooms.
    fileprivate func daySheet(_ calendar: CalendarStore) -> some View {
        ScrollView { detailBody(calendar, day: monthSheetDay ?? focus.day).padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m) }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .accessibilityIdentifier("month.day_sheet")
    }

    fileprivate var daySheetBinding: Binding<Bool> { Binding(get: { monthSheetDay != nil }, set: { if !$0 { monthSheetDay = nil } }) }

    fileprivate func daySheetOpened() {
        guard let day = monthSheetDay, let calendar else { return }
        calendar.showMonth(MonthKey(day: day) ?? calendar.visibleKey)
        Task { await calendar.ensureWindow(); await calendar.select(day) }
    }

    private func monthVisibleChanged(_ key: MonthKey) {
        guard let calendar else { return }
        calendar.showMonth(key)
        Task { await calendar.ensureWindow() }
    }

    /// Details of one day (the month list opens them in a sheet): the same sections as one day of the week zoom, plus the actions.
    private func detailBody(_ calendar: CalendarStore, day: LocalDay) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.m) {
            DayDetail(store: calendar, day: day, absenceRequest: $absenceRequest, sheet: interceptedSheet) {
                DayEntries(evaluation: calendar.detail, day: day, zone: timeList.calendar.timeZone,
                           onEdit: { editor = EditorRequest(segment: $0, day: day); touchedDay = day },
                           onVoid: { voiding = $0; touchedDay = day },
                           onAcknowledge: { segment in Task { if await timeList.acknowledge(segment) { await calendar.loadDetail() } } },
                           setLessons: { count in
                               let failure = await timeList.setSchoolLessons(count, on: day)
                               await calendar.loadDetail()
                               return failure
                           })
            }
        }
    }

    /// "Zeitabschnitt" in the day actions opens the same editor as everywhere else (no second form for entries).
    private var interceptedSheet: Binding<PlanSheet?> {
        Binding(get: { sheet }, set: { newValue in
            if case .manualEntry(let day)? = newValue { monthSheetDay = nil; editor = EditorRequest(segment: nil, day: day); touchedDay = day } else { sheet = newValue }
        })
    }

    @ViewBuilder private var weekContent: some View {
        if isPlanning, let planStore, let weekStore {
            VStack(spacing: 0) {
                HStack {
                    Z2.t("plan.mode_title").font(TTFont.cardTitle).foregroundStyle(TT.textPrimary)
                    Spacer()
                    Button { navigate { withAnimation(animation) { focus.isPlanning = false } } } label: { Z2.t("plan.done").frame(minHeight: 44) }
                        .buttonStyle(.borderless).accessibilityIdentifier("week.plan.done")
                }
                .padding(.horizontal, TT.Space.l)
                WeekPlannerView(store: planStore, overview: weekStore)
            }
        } else {
            VStack(spacing: 0) {
                WeekStrip(weekStart: focus.weekStart, days: timeList.days, selected: focus.day, today: today, namespace: selectionSpace, select: { day in
                    TTHaptics.play(.selection)
                    withAnimation(animation) { focus.select(day) }
                }, shift: { switchWeek($0) })
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge) // seven columns cannot grow with accessibility sizes
                .padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.xs)
                WeekPages(store: timeList, week: weekStore, focus: focus, position: $weekPage, canPlan: planStore != nil, canAct: calendar != nil,
                          startPlanning: { navigate { withAnimation(animation) { focus.isPlanning = true } } }, actions: dayActions,
                          openDay: { openDayDetail($0) }, settled: { weekPageSettled($0) })
            }
        }
    }

    /// The tap on a day header of the week list opens the day detail (plan, hints, warnings, entries) in the same sheet as the month list.
    private func openDayDetail(_ day: LocalDay) {
        guard calendar != nil else { return }
        TTHaptics.play(.selection)
        focus.select(day)
        monthSheetDay = day
    }

    private var weekAnchor: LocalDay { LocalDays.mondayOfWeek(containing: today) ?? focus.weekStart }
    private var focusWeekIndex: Int { WeekPages.index(of: focus.weekStart, anchor: weekAnchor) }

    /// A swipe came to rest on another week page: the anchor follows (same path as the arrow buttons).
    private func weekPageSettled(_ index: Int) {
        guard zoom == .week, !isPlanning, index != focusWeekIndex else { return }
        TTHaptics.play(.selection)
        focus.shiftWeeks(index - focusWeekIndex)
    }

    private var dayActions: DayActions {
        DayActions(
            add: { editor = EditorRequest(segment: nil, day: $0); touchedDay = $0 },
            edit: { editor = EditorRequest(segment: $0, day: $1); touchedDay = $1 },
            void: { voiding = $0; touchedDay = $1 },
            absence: { absenceRequest = AbsenceRequest(kind: $0, start: $1, end: $1) },
            plan: { sheet = .plan($0) },
            customDay: { sheet = .customDay($0) })
    }

    private func rangeBar(_ calendar: CalendarStore) -> some View {
        Card(padding: TT.Space.m) {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                if let range = calendar.chosenRange {
                    if calendar.rangeEnd == nil {
                        Text(Z2.s("range.pick_end \(PlanFormat.shortDay(range.start, calendar: calendar.calendar))")).font(TTFont.label)
                    } else {
                        Text("calendar.range.chosen \(PlanFormat.range(range.start, range.end, calendar: calendar.calendar))").font(TTFont.label)
                    }
                } else {
                    Text("calendar.range.hint").font(TTFont.label)
                }
                HStack {
                    ForEach([AbsenceKind.vacation, .sick], id: \.self) { kind in
                        Button {
                            guard let range = calendar.chosenRange else { return }
                            calendar.cancelRange()
                            absenceRequest = AbsenceRequest(kind: kind, start: range.start, end: range.end)
                        } label: { Label(kind.shortKey, systemImage: kind.ttSymbol).lineLimit(1).minimumScaleFactor(0.8) }
                            .buttonStyle(.ttSecondary).disabled(calendar.chosenRange == nil).accessibilityIdentifier("range.\(kind.rawValue)")
                    }
                    Spacer()
                    Button("common.cancel") { calendar.cancelRange() }.buttonStyle(.borderless).accessibilityIdentifier("range.cancel")
                }
            }
        }
    }

    // MARK: - Navigation

    /// Runs a navigation; asks first when the week planner holds unsaved changes.
    private func navigate(_ action: @escaping () -> Void) {
        if isPlanning, planStore?.isDirty == true { pendingNavigation = PendingNavigation(action: action) } else { action() }
    }

    private func setZoom(_ new: TimeZoom) {
        guard new != zoom else { return }
        TTHaptics.play(.softTap)
        navigate {
            withAnimation(animation) { focus.setZoom(new) }
            storedZoom = new.rawValue
            if new == .month { visibleMonth = focus.monthKey }
        }
    }

    private func goToToday() {
        TTHaptics.play(.softTap)
        navigate {
            withAnimation(animation) { focus.goToToday(today) }
            if zoom == .month { visibleMonth = focus.monthKey; jumpMonth(to: focus.monthKey, animated: true) }
        }
    }

    private func step(_ count: Int) {
        TTHaptics.play(.softTap)
        switch zoom {
        case .month: jumpMonth(to: visibleMonth.adding(count), animated: true)
        case .week: switchWeek(count)
        }
    }

    // MARK: - Week paging (U2)

    /// Arrows, "Heute", keyboard and VoiceOver: scroll the page view; the settled position then moves the anchor.
    private func switchWeek(_ count: Int) {
        guard zoom == .week, !isPlanning else { return }
        TTHaptics.play(.selection)
        let target = max(-WeekPages.reach, min(WeekPages.reach, (weekPage ?? focusWeekIndex) + count))
        if reduceMotion { weekPage = target } else { withAnimation(.smooth(duration: 0.35)) { weekPage = target } }
    }

    /// iPad keyboard (also iPad apps on a Mac): Command + arrow keys switch the week.
    @ViewBuilder private var weekKeyboardShortcuts: some View {
        if zoom == .week && !isPlanning {
            HStack {
                Button("") { switchWeek(-1) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("") { switchWeek(1) }.keyboardShortcut(.rightArrow, modifiers: .command)
            }
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func jump(to key: MonthKey) {
        TTHaptics.play(.selection)
        jumpMonth(to: key, animated: true)
    }

    private func tap(_ day: LocalDay, in calendar: CalendarStore) {
        if calendar.isRangeMode {
            let completes = calendar.rangeStart != nil && calendar.rangeEnd == nil
            TTHaptics.play(completes ? .success : .tap)
            calendar.tapInRangeMode(day)
            return
        }
        TTHaptics.play(.selection)
        withAnimation(animation) { focus.select(day) }
        monthSheetDay = day
    }

    /// The planning area ("Kommende Wochen") hands a week over: it opens in the planning mode of the week zoom.
    private func planStoreOpen(_ monday: LocalDay) {
        withAnimation(animation) {
            focus.setZoom(.week)
            focus.select(monday)
            focus.isPlanning = true
        }
        storedZoom = TimeZoom.week.rawValue
    }

    // MARK: - Loading

    private func syncStores() {
        switch focus.zoom {
        case .month:
            guard let calendar else { return }
            calendar.showMonth(visibleMonth)
            if calendar.selectedDay != focus.day { Task { await calendar.select(focus.day) } }
            Task { await calendar.ensureWindow() }
        case .week:
            if timeList.weekStart != focus.weekStart { Task { await timeList.open(week: focus.day) } }
            if let weekStore, weekStore.monday != focus.weekStart { Task { await weekStore.go(to: focus.day) } }
            if focus.isPlanning, let planStore, planStore.monday != focus.weekStart { Task { await planStore.open(monday: focus.weekStart) } }
        }
    }

    /// Loads what the current zoom shows (also when the zoom changes).
    private func load() async {
        switch zoom {
        case .month:
            guard let calendar else { return }
            calendar.showMonth(focus.monthKey)
            await calendar.ensureWindow()
            if calendar.selectedDay != focus.day { await calendar.select(focus.day) }
        case .week:
            if timeList.weekStart != focus.weekStart { await timeList.open(week: focus.day) } else { await timeList.load() }
            if let weekStore { if weekStore.monday != focus.weekStart { await weekStore.go(to: focus.day) } else { await weekStore.load() } }
            if focus.isPlanning, let planStore, planStore.monday != focus.weekStart { await planStore.open(monday: focus.weekStart) }
        }
    }

    private func reloadAll() async {
        switch zoom {
        case .month: await calendar?.load()
        case .week: await timeList.load(); await weekStore?.load()
        }
    }

    /// After an entry was created, corrected or voided: the week list, the week figures and the month's copy of the day are refreshed.
    fileprivate func refreshAfterEditPublic() { refreshAfterEdit() }
    private func refreshAfterEdit() {
        let day = touchedDay ?? focus.day
        Task {
            await timeList.load()
            await weekStore?.load()
            await calendar?.refreshEvaluation(day)
            if day != focus.day { await calendar?.refreshEvaluation(focus.day) }
        }
    }
}

/// Sheets that need the calendar store (absence editor, plan and custom-day sheets); without the planning module there are none.
private struct CalendarSheets: ViewModifier {
    let calendar: CalendarStore?
    @Binding var absenceRequest: AbsenceRequest?
    @Binding var sheet: PlanSheet?

    func body(content: Content) -> some View {
        if let calendar {
            content
                .absenceEditor($absenceRequest, actions: AbsenceEditorActions(calendar: calendar))
                .sheet(item: $sheet) { PlanSheetHost(sheet: $0, store: calendar) }
        } else {
            content
        }
    }
}

// MARK: - Header

/// Month or week title (large, left) with glass arrows. Same component for both zoom levels.
struct ZoomHeader<PickerContent: View>: View {
    let title: String
    let subtitle: String
    let opensPicker: Bool
    @Binding var picker: Bool
    let previous: () -> Void
    let next: () -> Void
    @ViewBuilder let pickerContent: () -> PickerContent

    var body: some View {
        HStack(spacing: TT.Space.s) {
            Button { if opensPicker { picker = true } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: title).font(.system(.largeTitle, design: .default, weight: .bold)).foregroundStyle(TT.textPrimary)
                    Text(verbatim: subtitle).font(.system(.title2, weight: .regular)).foregroundStyle(Color.accentColor)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.opacity)
            }
            .disabled(!opensPicker)
            .accessibilityLabel(Text(verbatim: "\(title) \(subtitle)"))
            .accessibilityIdentifier("calendar.title")
            .accessibilityHint(opensPicker ? Text("calendar.picker.hint") : Text(verbatim: ""))
            .popover(isPresented: $picker) { pickerContent().presentationCompactAdaptation(.popover) }
            Spacer(minLength: TT.Space.s)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: previous) { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(.rect) }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(Text(opensPicker ? "calendar.previous_month" : "time.previous_week")).accessibilityIdentifier("calendar.prev")
                    Button(action: next) { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(.rect) }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(Text(opensPicker ? "calendar.next_month" : "time.next_week")).accessibilityIdentifier("calendar.next")
                }
            }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Day entries (month zoom)

/// The recorded entries of one day inside the month zoom's detail. Same rows, same sheets as the week zoom.
struct DayEntries: View {
    let evaluation: DayEvaluation?
    let day: LocalDay
    let zone: TimeZone
    let onEdit: (Segment) -> Void
    let onVoid: (Segment) -> Void
    /// P15: clears the review marker of a flagged entry; nil hides the action.
    var onAcknowledge: ((Segment) -> Void)?
    /// P15: saves the school lesson count of the day (nil clears it); nil hides the picker.
    var setLessons: ((Int?) async -> TimetrackError?)?

    var body: some View {
        if let evaluation, evaluation.date == day {
            let segments = evaluation.timeRows.compactMap { row -> Segment? in if case .segment(let segment, _) = row { segment } else { nil } }
            if segments.isEmpty {
                Text("time.no_entries").font(TTFont.body).foregroundStyle(TT.textTertiary).padding(.vertical, TT.Space.xs)
                    .accessibilityIdentifier("day.entries.empty")
            } else {
                ListCard {
                    ForEach(segments) { segment in
                        SegmentRow(segment: segment, zone: zone)
                            .contentShape(.rect)
                            .onTapGesture { onEdit(segment) }
                            .contextMenu {
                                Button { onEdit(segment) } label: { Label("time.edit", systemImage: "pencil") }
                                if segment.needsReview && !segment.isRunning, let onAcknowledge {
                                    Button { onAcknowledge(segment) } label: { Label(p15Key("review.acknowledge"), systemImage: "checkmark.seal") }
                                }
                                Button(role: .destructive) { onVoid(segment) } label: { Label("time.void", systemImage: "xmark.circle") }
                            }
                            .accessibilityAction(named: Text("time.edit")) { onEdit(segment) }
                            .accessibilityAction(named: Text("time.void")) { onVoid(segment) }
                            .accessibilityActions {
                                if segment.needsReview && !segment.isRunning, let onAcknowledge {
                                    Button(p15("review.acknowledge")) { onAcknowledge(segment) }
                                }
                            }
                    }
                }
                .accessibilityIdentifier("day.entries")
            }
            if let setLessons, evaluation.hasLegalNotes { LegalDayNotes(day: evaluation, setLessons: setLessons) }
        }
    }
}
#endif

private struct DaySheet: ViewModifier {
    let hub: TimeHub

    func body(content: Content) -> some View {
        if let calendar = hub.calendar {
            content.sheet(isPresented: hub.daySheetBinding, onDismiss: hub.refreshAfterEditPublic) { hub.daySheet(calendar) }
        } else {
            content
        }
    }
}
