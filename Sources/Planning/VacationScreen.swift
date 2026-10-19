import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// The "Urlaub" tab: yearly balance, absences by state, quick actions and vacation settings.
struct VacationScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let store = model.planning {
                VacationContent(store: store)
            } else {
                ScrollView { EmptyState(symbol: "beach.umbrella", title: "vacation.disabled").padding(TT.Space.l) }.ttScreenBackground()
            }
        }
        .navigationTitle("sidebar.vacation")
    }
}

private struct VacationContent: View {
    let store: PlanningStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var request: AbsenceRequest?
    @State private var showSettings = false

    private var wide: Bool { planningIsWide(sizeClass) }
    private var today: LocalDay { store.today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                yearSwitcher
                if let error = store.error, !showSettings, request == nil { ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await store.load() } }.accessibilityIdentifier("error.banner") }
                if store.settings?.configured == false { HintBanner("vacation.not_configured") }
                #if os(iOS)
                VacationPlannerLink() // N1a: vacation suggestions (iOS/iPadOS)
                #endif
                if wide {
                    HStack(alignment: .top, spacing: TT.Space.xl) { balance.frame(maxWidth: 440); absences }
                } else {
                    balance
                    absences
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: wide ? 1100 : TT.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .task { await store.load(); await store.loadSettings() }
        .refreshable { await store.load() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showSettings = true } label: { Label("vacation.settings", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("vacation.settings")
                Menu {
                    AbsenceQuickMenuItems(start: today, end: today) { request = $0 }
                } label: { Label("plan.add", systemImage: "plus") }
                    .accessibilityIdentifier("vacation.add")
            }
        }
        .absenceEditor($request, actions: AbsenceEditorActions(planning: store))
        .sheet(isPresented: $showSettings) { VacationSettingsSheet(store: store) }
    }

    private var yearSwitcher: some View {
        HStack {
            Button { Task { await store.shiftYears(-1) } } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }
                .accessibilityLabel(Text("vacation.previous_year"))
            Spacer()
            Text(verbatim: String(store.year)).font(TTFont.sectionTitle).monospacedDigit().foregroundStyle(TT.textPrimary).accessibilityIdentifier("vacation.year")
            Spacer()
            Button { Task { await store.shiftYears(1) } } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                .accessibilityLabel(Text("vacation.next_year"))
        }
        .buttonStyle(.borderless).padding(.horizontal, TT.Space.s)
    }

    @ViewBuilder private var balance: some View {
        if let balance = store.balance {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                SectionHeader("vacation.balance")
                Card {
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: TT.Space.l)) : AnyLayout(HStackLayout(spacing: TT.Space.xl))
                    layout {
                        let total = balance.entitlementHalfDays + balance.carryOverHalfDays + balance.adjustmentHalfDays
                        ProgressRing(progress: total > 0 ? Double(max(balance.availableHalfDays, 0)) / Double(total) : 0, lineWidth: 12, tint: TT.kindVacation) {
                            Image(systemName: "beach.umbrella.fill").font(.title2).foregroundStyle(TT.kindVacation)
                        }
                        .frame(width: 96, height: 96)
                        VStack(alignment: .leading, spacing: TT.Space.xs) {
                            Text("vacation.available").font(TTFont.label).foregroundStyle(TT.textSecondary)
                            Text("vacation.days \(HalfDayFormat.days(balance.availableHalfDays))")
                                .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(TT.textPrimary)
                                .accessibilityIdentifier("vacation.available.value")
                            Text("vacation.after_planned_short \(HalfDayFormat.days(balance.availableAfterPlannedHalfDays))").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ListCard {
                    if let date = balance.snapshotDate, let rest = balance.snapshotRemainingHalfDays {
                        FormRow("vacation.snapshot_row \(PlanFormat.shortDay(date, calendar: store.calendar))") { Text("vacation.days \(HalfDayFormat.days(rest))").monospacedDigit() }
                    } else {
                        row("vacation.entitlement", balance.entitlementHalfDays)
                        if balance.carryOverHalfDays != 0 { row("vacation.carry_over", balance.carryOverHalfDays) }
                    }
                    if balance.adjustmentHalfDays != 0 { row("vacation.adjustment", balance.adjustmentHalfDays) }
                    row("vacation.booked", balance.bookedHalfDays)
                    row("vacation.planned", balance.plannedHalfDays)
                }
                Text("vacation.balance_formula").font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.xs)
            }
        } else if store.isLoading {
            SkeletonList(rows: 3)
        }
    }

    private var upcoming: [Absence] { store.absences.filter { $0.status == .planned || $0.status == .requested } }
    private var booked: [Absence] { store.absences.filter { $0.status != .planned && $0.status != .requested } }

    private var absences: some View {
        VStack(alignment: .leading, spacing: TT.Space.l) {
            if store.absences.isEmpty && !store.isLoading {
                SectionHeader("vacation.absences")
                Card { EmptyState(symbol: "calendar", title: "vacation.none", message: "vacation.none_hint") }
            } else {
                group("vacation.group.planned", upcoming)
                group("vacation.group.booked", booked)
            }
        }
    }

    @ViewBuilder private func group(_ title: LocalizedStringKey, _ list: [Absence]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                SectionHeader(title) { Text(verbatim: "\(list.count)") }
                ListCard {
                    ForEach(list) { absence in
                        Button { request = AbsenceRequest(kind: absence.kind, start: absence.startDate, end: absence.endDate, editing: absence) } label: {
                            AbsenceRow(absence: absence, calendar: store.calendar)
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("absence.row")
                    }
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ halfDays: Int) -> some View {
        FormRow(title) { Text("vacation.days \(HalfDayFormat.days(halfDays))").monospacedDigit() }
    }
}

struct AbsenceRow: View {
    let absence: Absence
    let calendar: DayCalendar

    var body: some View {
        HStack(spacing: TT.Space.m) {
            KindGlyph(symbol: absence.kind.ttSymbol, tint: absence.kind.ttTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(absence.kind.ttTitle).font(TTFont.body).foregroundStyle(TT.textPrimary)
                Text(verbatim: PlanFormat.range(absence.startDate, absence.endDate, calendar: calendar)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
            Spacer(minLength: TT.Space.s)
            VStack(alignment: .trailing, spacing: 4) {
                StatusChip(verbatim: absence.status.plainName, tone: absence.status.tone)
                if absence.kind == .vacation {
                    Text("vacation.days \(HalfDayFormat.days(absence.countedHalfDays))").font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary)
                }
            }
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Settings

struct VacationSettingsSheet: View {
    let store: PlanningStore
    @Environment(\.dismiss) private var dismiss
    @State private var region = "DE-ST"
    @State private var entitlement = "30"
    @State private var carry = "0"
    @State private var expiry = ""
    @State private var snapshotDate: LocalDay = ""
    @State private var snapshotDays = ""
    @State private var adjustDate: LocalDay = ""
    @State private var adjustDays = ""
    @State private var adjustReason = ""
    @State private var saving = false
    @State private var invalid: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    Text("vacation.settings_text").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    if store.settings?.configured == false { HintBanner("vacation.settings_suggestion") }
                    FormSection("vacation.region", footer: "vacation.region_hint") {
                        EditorRow {
                            Picker("vacation.region", selection: $region) { ForEach(VacationRegions.all, id: \.code) { Text(verbatim: $0.name).tag($0.code) } }
                                .pickerStyle(.menu).labelsHidden().accessibilityIdentifier("settings.region")
                        }
                    }
                    FormSection("vacation.entitlement_field", footer: "vacation.entitlement_hint") {
                        TextField("vacation.entitlement_field", text: $entitlement).padding(TT.Space.l).accessibilityIdentifier("settings.entitlement")
                    }
                    FormSection("vacation.carry_field \(String(store.year))", footer: "vacation.carry_hint") {
                        TextField("vacation.carry_field \(String(store.year))", text: $carry).padding(TT.Space.l).accessibilityIdentifier("settings.carry")
                    }
                    FormSection("vacation.expiry", footer: "vacation.expiry_hint") {
                        TextField("vacation.expiry_placeholder", text: $expiry).padding(TT.Space.l).accessibilityIdentifier("settings.expiry")
                    }
                    if let invalid { HintBanner(invalid, symbol: "exclamationmark.triangle.fill") }
                    if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.dismiss") { store.error = nil } }
                    Button("vacation.settings_save") { Task { await save() } }.buttonStyle(.ttPrimary).disabled(saving).accessibilityIdentifier("settings.save")
                    snapshotSection
                    adjustmentSection
                    entriesSection
                }
                .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle("vacation.settings").inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { dismiss() }.accessibilityIdentifier("settings.done") } }
        }
        .environment(\.timeZone, store.calendar.timeZone)
        .onAppear(perform: load)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    private var snapshotSection: some View {
        FormSection("vacation.snapshot_title", footer: "vacation.snapshot_text") {
            EditorRow { DatePicker("vacation.snapshot_date", selection: dayBinding($snapshotDate, calendar: store.calendar), displayedComponents: .date) }
            TextField("vacation.snapshot_days", text: $snapshotDays).padding(TT.Space.l)
            Button("vacation.snapshot_save") {
                guard let half = HalfDayFormat.parseHalfDays(snapshotDays), half >= 0 else { invalid = "vacation.error_days"; return }
                invalid = nil
                Task { if await store.addSnapshot(date: snapshotDate, remainingHalfDays: half) { snapshotDays = "" } }
            }
            .buttonStyle(.ttSecondary).padding(TT.Space.l)
        }
    }

    private var adjustmentSection: some View {
        FormSection("vacation.adjustment_title", footer: "vacation.adjustment_text") {
            EditorRow { DatePicker("vacation.adjustment_date", selection: dayBinding($adjustDate, calendar: store.calendar), displayedComponents: .date) }
            TextField("vacation.adjustment_days", text: $adjustDays).padding(TT.Space.l)
            TextField("vacation.adjustment_reason", text: $adjustReason).padding(TT.Space.l)
            Button("vacation.adjustment_save") {
                guard let half = HalfDayFormat.parseHalfDays(adjustDays), half != 0 else { invalid = "vacation.error_adjust_days"; return }
                let reason = adjustReason.trimmingCharacters(in: .whitespaces)
                guard !reason.isEmpty else { invalid = "vacation.error_reason"; return }
                invalid = nil
                Task { if await store.addAdjustment(date: adjustDate, halfDays: half, reason: String(reason.prefix(200))) { adjustDays = ""; adjustReason = "" } }
            }
            .buttonStyle(.ttSecondary).padding(TT.Space.l)
        }
    }

    @ViewBuilder private var entriesSection: some View {
        let entries = store.entries
        if !entries.snapshots.isEmpty || !entries.adjustments.isEmpty {
            VStack(alignment: .leading, spacing: TT.Space.s) {
                SectionHeader("vacation.entries_title \(String(store.year))")
                ListCard {
                    ForEach(entries.snapshots) { entry in
                        entryRow(Text("vacation.entry_snapshot \(PlanFormat.fullDay(entry.date, calendar: store.calendar)) \(HalfDayFormat.days(entry.remainingHalfDays))"), id: entry.id)
                    }
                    ForEach(entries.adjustments) { entry in
                        entryRow(Text("vacation.entry_adjustment \(PlanFormat.fullDay(entry.date, calendar: store.calendar)) \(HalfDayFormat.days(entry.halfDays)) \(entry.reason)"), id: entry.id)
                    }
                }
            }
        }
    }

    private func entryRow(_ text: Text, id: UUID) -> some View {
        HStack {
            text.font(TTFont.body).foregroundStyle(TT.textPrimary)
            Spacer()
            Button(role: .destructive) { Task { await store.deleteEntry(id: id) } } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).accessibilityLabel(Text("vacation.entry_delete"))
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
    }

    private func load() {
        store.error = nil
        snapshotDate = store.today
        adjustDate = store.today
        if let settings = store.settings {
            region = settings.region
            entitlement = HalfDayFormat.days(settings.annualEntitlementHalfDays).replacingOccurrences(of: "-", with: "")
            carry = HalfDayFormat.days(settings.carryOverByYear?[String(store.year)] ?? 0)
            expiry = settings.carryOverExpiry.map(Self.displayExpiry) ?? ""
        }
    }

    private static func displayExpiry(_ mmdd: String) -> String {
        let parts = mmdd.split(separator: "-")
        return parts.count == 2 ? "\(parts[1]).\(parts[0])." : mmdd
    }

    /// "31.03." or "31.03" to `MM-DD`.
    static func parseExpiry(_ text: String) -> String?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        let parts = trimmed.split(separator: ".").map(String.init)
        guard parts.count >= 2, let day = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month), (1...31).contains(day) else { return nil }
        return .some(String(format: "%02d-%02d", month, day))
    }

    private func save() async {
        guard let entitlementHalf = HalfDayFormat.parseHalfDays(entitlement), entitlementHalf >= 0 else { invalid = "vacation.error_days"; return }
        guard let carryHalf = HalfDayFormat.parseHalfDays(carry), carryHalf >= 0 else { invalid = "vacation.error_days"; return }
        guard let expiryValue = Self.parseExpiry(expiry) else { invalid = "vacation.error_expiry"; return }
        invalid = nil
        saving = true
        defer { saving = false }
        var new = store.settings ?? VacationSettings()
        new.region = region
        new.annualEntitlementHalfDays = entitlementHalf
        var carryMap = new.carryOverByYear ?? [:]
        carryMap[String(store.year)] = carryHalf
        new.carryOverByYear = carryMap
        new.carryOverExpiry = expiryValue
        _ = await store.saveSettings(new)
    }
}
