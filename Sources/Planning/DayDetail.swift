import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Everything about one day plus direct actions (absences, plan, custom day, time entry).
struct DayDetail: View {
    let store: CalendarStore
    let day: LocalDay
    @Binding var absenceRequest: AbsenceRequest?
    @Binding var sheet: PlanSheet?
    var showTitle = true
    @Environment(AppModel.self) private var model
    @State private var cancelling: Absence?

    var body: some View {
        let info = store.info(for: day)
        VStack(alignment: .leading, spacing: TT.Space.m) {
            if showTitle { Eyebrow(verbatim: PlanFormat.longDay(day, calendar: store.calendar)).accessibilityAddTraits(.isHeader) }
            evaluation
            if !info.holidays.isEmpty || !info.schoolHolidays.isEmpty { holidays(info) }
            if !info.absences.isEmpty { absences(info) }
            planRow(info)
            actions
        }
        .confirmationDialog("plan.cancel.title", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }), titleVisibility: .visible) {
            Button("plan.cancel.confirm", role: .destructive) { if let absence = cancelling { Task { await store.cancelAbsence(absence) } } }
        } message: { Text("plan.cancel.message") }
    }

    @ViewBuilder private var evaluation: some View {
        if let detail = store.detail, detail.date == day {
            Card(padding: TT.Space.m) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("calendar.evaluation").font(TTFont.label).foregroundStyle(TT.textSecondary)
                        Text("calendar.evaluation_text \(DurationFormat.hoursMinutes(detail.targetSeconds)) \(DurationFormat.hoursMinutes(detail.evaluatedWorkSeconds + detail.creditSeconds))")
                            .font(TTFont.numeral).foregroundStyle(TT.textPrimary)
                    }
                    Spacer()
                    if let mark = detail.mark, mark != .unmarked, mark != .unknown { StatusChip(markKeyPlan(mark), tone: .neutral) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func markKeyPlan(_ mark: DayMarkKind) -> LocalizedStringKey {
        switch mark {
        case .holiday: "mark.holiday"
        case .vacation: "mark.vacation"
        case .sick: "mark.sick"
        case .excused: "mark.excused"
        case .schoolCredit: "mark.school_credit"
        case .unmarked, .unknown: "time.no_entries"
        }
    }

    private func holidays(_ info: CalendarDayInfo) -> some View {
        ListCard {
            ForEach(info.holidays + info.schoolHolidays, id: \.identity) { entry in
                HStack(spacing: TT.Space.m) {
                    KindGlyph(symbol: entry.kind == .holiday ? "party.popper.fill" : "backpack.fill", tint: TT.kindHoliday)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: entry.name).font(TTFont.body).foregroundStyle(TT.textPrimary)
                        Text(entry.kind == .holiday ? "mark.holiday" : "calendar.school_holiday").font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    }
                    Spacer()
                    if entry.source == .custom {
                        StatusChip("calendar.custom", tone: .neutral)
                        Button(role: .destructive) { Task { await store.deleteCustomDay(entry) } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).accessibilityLabel(Text("calendar.custom_delete")).accessibilityIdentifier("custom.delete")
                    }
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func absences(_ info: CalendarDayInfo) -> some View {
        ListCard {
            ForEach(info.absences) { absence in
                Button { absenceRequest = AbsenceRequest(kind: absence.kind, start: absence.startDate, end: absence.endDate, editing: absence) } label: {
                    HStack(spacing: TT.Space.m) {
                        KindGlyph(symbol: absence.kind.ttSymbol, tint: absence.kind.ttTint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(absence.kind.ttTitle).font(TTFont.body).foregroundStyle(TT.textPrimary)
                            Text(verbatim: PlanFormat.range(absence.startDate, absence.endDate, calendar: store.calendar)).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                            if absence.kind == .sick, let doc = absence.documentStatus, doc != .notNeeded {
                                Text(verbatim: String(localized: "calendar.document_line \(doc.plainName)")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                            }
                        }
                        Spacer(minLength: TT.Space.s)
                        VStack(alignment: .trailing, spacing: 4) {
                            StatusChip(verbatim: absence.status.plainName, tone: absence.status.tone)
                            if absence.kind == .vacation { Text(verbatim: PlanFormat.days(absence.countedHalfDays)).font(TTFont.numeralSmall).foregroundStyle(TT.textSecondary) }
                        }
                    }
                    .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.m)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("absence.row")
                .contextMenu {
                    Button { absenceRequest = AbsenceRequest(kind: absence.kind, start: absence.startDate, end: absence.endDate, editing: absence) } label: { Label("plan.edit", systemImage: "pencil") }
                    if absence.kind == .sick, absence.documentStatus != .submitted {
                        Button { Task { await store.markDocumentSubmitted(absence) } } label: { Label("plan.document.mark_submitted", systemImage: "doc.badge.checkmark") }
                    }
                    Button(role: .destructive) { cancelling = absence } label: { Label("plan.cancel.action", systemImage: "xmark.circle") }
                }
                .accessibilityAction(named: Text("plan.edit")) { absenceRequest = AbsenceRequest(kind: absence.kind, start: absence.startDate, end: absence.endDate, editing: absence) }
            }
        }
    }

    private func planRow(_ info: CalendarDayInfo) -> some View {
        Card(padding: TT.Space.m) {
            HStack(spacing: TT.Space.m) {
                if let plan = info.plan {
                    KindGlyph(symbol: plan.mode.symbol, tint: plan.mode.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("calendar.plan_label \(plan.mode.plainName)").font(TTFont.body).foregroundStyle(TT.textPrimary)
                        if let note = plan.note, !note.isEmpty { Text(verbatim: note).font(TTFont.meta).foregroundStyle(TT.textSecondary) }
                    }
                } else {
                    Text("calendar.no_plan").font(TTFont.body).foregroundStyle(TT.textSecondary)
                }
                Spacer()
                Button(info.plan == nil ? "plan.action.plan" : "plan.edit") { sheet = .plan(day) }.buttonStyle(.borderless).accessibilityIdentifier("day.plan")
            }
        }
    }

    private var actions: some View {
        let columns = [GridItem(.adaptive(minimum: 140), spacing: TT.Space.s)]
        return LazyVGrid(columns: columns, spacing: TT.Space.s) {
            ForEach(AbsenceKind.selectable, id: \.self) { kind in
                Button { absenceRequest = AbsenceRequest(kind: kind, start: day, end: day) } label: { Label(kind.shortKey, systemImage: kind.ttSymbol).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity) }
                    .buttonStyle(.ttSecondary).accessibilityLabel(Text(kind.actionKey)).accessibilityIdentifier("day.\(kind.rawValue)")
            }
            Button { sheet = .customDay(day) } label: { Label("plan.short.custom_day", systemImage: "flag").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity) }
                .buttonStyle(.ttSecondary).accessibilityIdentifier("day.custom")
            if model.timeList != nil {
                Button { sheet = .manualEntry(day) } label: { Label("plan.short.segment", systemImage: "clock.badge.plus").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity) }
                    .buttonStyle(.ttSecondary).accessibilityIdentifier("day.segment")
            }
        }
    }
}
