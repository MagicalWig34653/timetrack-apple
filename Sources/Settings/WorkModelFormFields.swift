import SwiftUI
import TimetrackCore
import TimetrackDesign

/// The editable fields of a work model version, shared by the correction sheet and the "new version" sheet (WM2).
/// `showsEnd == false` hides the end date (a new version is open-ended; ending is its own action).
struct WorkModelFormFields: View {
    @Binding var form: WorkModelForm
    let calendar: DayCalendar
    var showsEnd = true
    /// Label of the start date ("Gültig ab" in a correction, "Neue Version gilt ab" for a new version).
    var startLabel: LocalizedStringKey = "workmodel.valid_from"

    private var invalid: Set<WorkModelForm.Field> {
        if case .failure(let errors) = form.build() { return errors.fields }
        return []
    }

    private func flag(_ field: WorkModelForm.Field) -> Bool { invalid.contains(field) }

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.l) {
            scheduleSection
            roundingSection
            schoolSection
            breaksSection
            if form.dailyTargetSeconds != nil {
                HintBanner("workmodel.daily_override")
                Button("workmodel.daily_override_remove") { form.dailyTargetSeconds = nil }.buttonStyle(.ttSecondary)
            }
        }
    }

    private func field(_ key: LocalizedStringKey, _ text: Binding<String>, _ field: WorkModelForm.Field, hint: LocalizedStringKey? = nil, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key).font(TTFont.meta).foregroundStyle(flag(field) ? TT.danger : TT.textSecondary)
            TextField(key, text: text)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityIdentifier(id)
            if flag(field) { Text("workmodel.invalid").font(TTFont.meta).foregroundStyle(TT.danger) }
            else if let hint { Text(hint).font(TTFont.meta).foregroundStyle(TT.textTertiary) }
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
    }

    private var openEnded: Binding<Bool> {
        Binding(get: { form.validTo.isEmpty }, set: { form.validTo = $0 ? "" : max(form.validFrom, calendar.day(for: .now)) })
    }

    private var scheduleSection: some View {
        FormSection("workmodel.section_schedule") {
            EditorRow { DatePicker(startLabel, selection: dayBinding($form.validFrom, calendar: calendar), displayedComponents: .date).accessibilityIdentifier("workmodel.valid_from") }
            if showsEnd {
                EditorRow { Toggle("workmodel.open_end_toggle", isOn: openEnded) }
                if !form.validTo.isEmpty {
                    EditorRow { DatePicker("workmodel.valid_to", selection: dayBinding($form.validTo, calendar: calendar), displayedComponents: .date) }
                    if flag(.validTo) { Text("workmodel.invalid").font(TTFont.meta).foregroundStyle(TT.danger).padding(.horizontal, TT.Space.l) }
                }
            }
            field("workmodel.weekly", $form.weeklyTarget, .weekly, hint: "workmodel.weekly_hint", id: "workmodel.field.weekly")
            VStack(alignment: .leading, spacing: TT.Space.s) {
                Text("workmodel.workdays").font(TTFont.meta).foregroundStyle(flag(.workdays) ? TT.danger : TT.textSecondary)
                HStack(spacing: TT.Space.xs) {
                    ForEach(1...7, id: \.self) { day in
                        let on = form.workdays.contains(day)
                        Button { if on { form.workdays.remove(day) } else { form.workdays.insert(day) } } label: {
                            Text(verbatim: WorkModelCard.workdays([day])).font(TTFont.label).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(on ? Color.primary : TT.textSecondary)
                                .background(on ? TT.surfaceRaised : Color.clear, in: .rect(cornerRadius: TT.Radius.chip))
                                .overlay { RoundedRectangle(cornerRadius: TT.Radius.chip).strokeBorder(on ? TT.textSecondary : TT.separator, lineWidth: on ? 2 : 1) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("workmodel.day.\(day)")
                    }
                }
                if flag(.workdays) { Text("workmodel.invalid_workdays").font(TTFont.meta).foregroundStyle(TT.danger) }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            field("workmodel.timezone", $form.timezone, .timezone, id: "workmodel.field.timezone")
            field("workmodel.boundary", $form.dayBoundaryMinutes, .dayBoundary, hint: "workmodel.boundary_hint", id: "workmodel.field.boundary")
        }
    }

    private var roundingSection: some View {
        FormSection("workmodel.rounding", footer: "workmodel.rounding_hint") {
            EditorRow { Toggle("workmodel.rounding_enabled", isOn: $form.roundingEnabled) }
            if form.roundingEnabled { field("workmodel.rounding_minutes", $form.roundingMinutes, .roundingMinutes, id: "workmodel.field.rounding") }
            EditorRow { Toggle("workmodel.travel", isOn: $form.travelCountsAsWork) }
        }
    }

    private var schoolSection: some View {
        FormSection("workmodel.section_school") {
            field("workmodel.school_threshold", $form.schoolThreshold, .schoolThreshold, hint: "workmodel.school_threshold_hint", id: "workmodel.field.school_threshold")
            field("workmodel.school_credit", $form.schoolCredit, .schoolCredit, hint: "workmodel.school_credit_hint", id: "workmodel.field.school_credit")
        }
    }

    private var breaksSection: some View {
        FormSection("workmodel.breaks", footer: "workmodel.breaks_hint") {
            ForEach(form.fixedBreaks.indices, id: \.self) { index in
                HStack(spacing: TT.Space.s) {
                    TextField("workmodel.break_from", text: $form.fixedBreaks[index].start).frame(maxWidth: 90)
                    Text(verbatim: "–").foregroundStyle(TT.textSecondary)
                    TextField("workmodel.break_to", text: $form.fixedBreaks[index].end).frame(maxWidth: 90)
                    Spacer(minLength: 0)
                    Button(role: .destructive) { form.fixedBreaks.remove(at: index) } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                        .buttonStyle(.borderless).accessibilityLabel(Text("workmodel.break_remove"))
                }
                .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.xs)
            }
            if flag(.fixedBreaks) { Text("workmodel.invalid_breaks").font(TTFont.meta).foregroundStyle(TT.danger).padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s) }
            Button { form.fixedBreaks.append(FixedBreak(start: "12:00", end: "12:30")) } label: { Label("workmodel.break_add", systemImage: "plus") }
                .buttonStyle(.ttSecondary).padding(TT.Space.l)
        }
    }
}
