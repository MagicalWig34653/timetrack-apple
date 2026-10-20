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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.deviceCalendar) private var deviceCalendar
    @AppStorage("time.zoom") private var storedZoom = TimeZoom.month.rawValue

    @State private var focus: TimeFocus
    @State private var pagerPosition: Int?
    @State private var editor: EditorRequest?
    @State private var voiding: Segment?
    @State private var touchedDay: LocalDay?
    @State private var absenceRequest: AbsenceRequest?
    @State private var sheet: PlanSheet?
    @State private var picker = false
    @State private var pendingNavigation: PendingNavigation?
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
        _pagerPosition = State(initialValue: MonthKey(day: today)?.index)
    }

    // MARK: - Derived

    private var wide: Bool { sizeClass == .regular }
    private var animation: Animation { Z2Motion.spring(reduceMotion: reduceMotion) }
    private var planEnabled: Bool { model.isEnabled(.planning) && model.apiClient != nil }
    private var zoom: TimeZoom { calendar == nil ? .week : focus.zoom }
    private var today: LocalDay { timeList.calendar.day(for: .now) }
    private var weekStore: WeekStore? { model.apiClient.map { WeekStoreCache.shared.weekStore($0, calendar: model.dayCalendar) } }
    private var planStore: WeekPlanStore? {
        guard planEnabled, let client = model.apiClient else { return nil }
        return WeekStoreCache.shared.planStore(client, calendar: model.dayCalendar)
    }
    private var isPlanning: Bool { zoom == .week && focus.isPlanning && planStore != nil }
    private var rowHeight: CGFloat { wide ? 84 : 48 }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ZoomHeader(title: headerTitle, subtitle: headerSubtitle, opensPicker: zoom == .month, picker: $picker, previous: { step(-1) }, next: { step(1) },
                       pickerContent: { calendar.map { store in MonthPicker(store: store) { picker = false; jump(to: store.visibleKey) } } })
                .padding(.horizontal, TT.Space.l)
            if let calendar, zoom == .month, calendar.isRangeMode { rangeBar(calendar).padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.s) }
            content
        }
        .ttScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $editor, onDismiss: refreshAfterEdit) { request in
            SegmentEditor(store: timeList, segment: request.segment, day: request.day)
                .presentationDetents([.fraction(0.75), .large])
        }
        .sheet(item: $voiding, onDismiss: refreshAfterEdit) { segment in VoidSheet(store: timeList, segment: segment) }
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
        .onChange(of: pagerPosition) { _, new in pagerSettled(new) }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await reloadAll() } } }
        .onChange(of: calendar?.planDays) { syncDeviceCalendar() }
        .onChange(of: calendar?.absences) { syncDeviceCalendar() }
        .onChange(of: deviceCalendar?.preferences) { syncDeviceCalendar() }
        .onAppear { planStore?.onSaved = { Task { await weekStore?.load(); await timeList.load() } } }
    }

    // MARK: - Header and toolbar

    private var headerTitle: String {
        switch zoom {
        case .month: PlanFormat.monthName(focus.monthKey.month, calendar: timeList.calendar)
        case .week: W.s("nav.kw", LocalDays.isoWeek(of: focus.weekStart) ?? 0)
        }
    }

    private var headerSubtitle: String {
        switch zoom {
        case .month: String(focus.monthKey.year)
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
                .pickerStyle(.segmented).frame(width: 190)
                .accessibilityIdentifier("time.zoom")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { goToToday() } label: { Text("calendar.today") }.accessibilityIdentifier("time.today")
            if let calendar, zoom == .month {
                Button { calendar.beginRange(at: focus.day) } label: { Label("plan.action.range", systemImage: "calendar.day.timeline.leading") }
                    .accessibilityIdentifier("calendar.range")
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
        Group {
            if wide {
                HStack(alignment: .top, spacing: TT.Space.xl) {
                    VStack(alignment: .leading, spacing: TT.Space.m) { grid(calendar); Legend(); Spacer(minLength: 0) }.frame(maxWidth: 640)
                    detailScroll(calendar).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, TT.Space.l).frame(maxWidth: 1200).frame(maxWidth: .infinity)
            } else {
                VStack(spacing: TT.Space.s) {
                    grid(calendar).padding(.horizontal, TT.Space.l)
                    detailScroll(calendar)
                }
            }
        }
    }

    private func grid(_ calendar: CalendarStore) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("calendar.week_short").frame(width: 26).accessibilityHidden(true)
                ForEach(PlanFormat.weekdayHeaders, id: \.self) { Text(verbatim: String($0.prefix(2))).frame(maxWidth: .infinity) }
            }
            .font(TTFont.eyebrow).foregroundStyle(TT.textTertiary).padding(.bottom, TT.Space.xs)
            MonthPager(store: calendar, position: $pagerPosition, selected: focus.day, rowHeight: rowHeight, namespace: selectionSpace,
                       onTap: { tap($0, in: calendar) }, onLongPress: { calendar.beginRange(at: $0); TTHaptics.play(.tap) })
        }
    }

    /// Details of the selected day: the same sections as one day of the week zoom, plus the actions. The grid above stays put.
    private func detailScroll(_ calendar: CalendarStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                DayDetail(store: calendar, day: focus.day, absenceRequest: $absenceRequest, sheet: interceptedSheet) {
                    DayEntries(evaluation: calendar.detail, day: focus.day, zone: timeList.calendar.timeZone,
                               onEdit: { editor = EditorRequest(segment: $0, day: focus.day); touchedDay = focus.day },
                               onVoid: { voiding = $0; touchedDay = focus.day })
                }
                if !wide { Legend() }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
            .frame(maxWidth: wide ? .infinity : TT.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await calendar.load(); await calendar.loadDetail() }
    }

    /// "Zeitabschnitt" in the day actions opens the same editor as everywhere else (no second form for entries).
    private var interceptedSheet: Binding<PlanSheet?> {
        Binding(get: { sheet }, set: { newValue in
            if case .manualEntry(let day)? = newValue { editor = EditorRequest(segment: nil, day: day); touchedDay = day } else { sheet = newValue }
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
                WeekStrip(weekStart: focus.weekStart, days: timeList.days, selected: focus.day, today: today, namespace: selectionSpace) { day in
                    TTHaptics.play(.selection)
                    withAnimation(animation) { focus.select(day) }
                }
                .padding(.horizontal, TT.Space.l).padding(.bottom, TT.Space.xs)
                WeekDayList(store: timeList, week: weekStore, selected: focus.day, canPlan: planStore != nil, canAct: calendar != nil,
                            startPlanning: { navigate { withAnimation(animation) { focus.isPlanning = true } } },
                            actions: dayActions)
            }
        }
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
                    Text("calendar.range.chosen \(PlanFormat.range(range.start, range.end, calendar: calendar.calendar))").font(TTFont.label)
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
            if new == .month { pagerPosition = focus.monthKey.index }
        }
    }

    private func goToToday() {
        TTHaptics.play(.softTap)
        navigate {
            withAnimation(animation) { focus.goToToday(today) }
            if zoom == .month { withAnimation(animation) { pagerPosition = focus.monthKey.index } }
        }
    }

    private func step(_ count: Int) {
        TTHaptics.play(.softTap)
        switch zoom {
        case .month: withAnimation(animation) { pagerPosition = (pagerPosition ?? focus.monthKey.index) + count }
        case .week: navigate { withAnimation(animation) { focus.shiftWeeks(count) } }
        }
    }

    private func jump(to key: MonthKey) {
        TTHaptics.play(.selection)
        withAnimation(animation) { pagerPosition = key.index }
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
    }

    /// The pager came to rest on another month: the anchor moves into it (today when visible, otherwise the 1st).
    private func pagerSettled(_ index: Int?) {
        guard zoom == .month, let index, index != focus.monthKey.index else { return }
        TTHaptics.play(.selection)
        withAnimation(animation) { focus.move(toMonth: MonthKey(index: index), preferring: today) }
    }

    // MARK: - Loading

    private func syncStores() {
        switch focus.zoom {
        case .month:
            guard let calendar else { return }
            calendar.showMonth(focus.monthKey)
            if pagerPosition != focus.monthKey.index { withAnimation(animation) { pagerPosition = focus.monthKey.index } }
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
            syncDeviceCalendar()
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
    private func refreshAfterEdit() {
        let day = touchedDay ?? focus.day
        Task {
            await timeList.load()
            await weekStore?.load()
            await calendar?.refreshEvaluation(day)
            if day != focus.day { await calendar?.refreshEvaluation(focus.day) }
        }
    }

    /// E1/E2: mirrors the visible plan days and the planned vacation/sick days into the calendars the user set to "Lesen + Schreiben".
    private func syncDeviceCalendar() {
        guard let calendar, let deviceCalendar, !deviceCalendar.preferences.writeCalendarIDs.isEmpty, !calendar.isLoading else { return }
        let range = calendar.visibleKey.gridRange
        deviceCalendar.sync(planDays: calendar.planDays, absences: calendar.absences, from: range.from, to: range.to, calendar: calendar.calendar) { "Arbeit: \($0.plainName)" }
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
                    Button(action: previous) { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(Text(opensPicker ? "calendar.previous_month" : "time.previous_week")).accessibilityIdentifier("calendar.prev")
                    Button(action: next) { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
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
                                Button(role: .destructive) { onVoid(segment) } label: { Label("time.void", systemImage: "xmark.circle") }
                            }
                            .accessibilityAction(named: Text("time.edit")) { onEdit(segment) }
                            .accessibilityAction(named: Text("time.void")) { onVoid(segment) }
                    }
                }
                .accessibilityIdentifier("day.entries")
            }
        }
    }
}
