import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// WM2 strings (table `WM2`, German is the source language).
func wm(_ key: String.LocalizationValue) -> String { String(localized: key, table: "WM2") }
func wmKey(_ key: String.LocalizationValue) -> LocalizedStringKey { LocalizedStringKey(wm(key)) }

/// Sheets of the work model screen besides the correction.
enum WorkModelSheet: Identifiable {
    case edit(WorkModel)
    case new
    case end(WorkModel)

    var id: String {
        switch self {
        case .edit(let model): "edit-\(model.id)"
        case .new: "new"
        case .end(let model): "end-\(model.id)"
        }
    }
}

// MARK: - New version

/// New version from a date on: the running predecessor ends the day before, the past stays untouched. Mirrors the PWA's "Ab einem Datum ändern".
struct WorkModelNewSheet: View {
    let store: WorkModelStore
    let calendar: DayCalendar
    @Environment(\.dismiss) private var dismiss
    @State private var form: WorkModelForm
    @State private var confirming = false
    @State private var saving = false

    init(store: WorkModelStore, calendar: DayCalendar) {
        self.store = store
        self.calendar = calendar
        let today = calendar.day(for: .now)
        if let newest = store.newestFirst.first {
            let after = newest.validTo.flatMap { LocalDays.adding(1, to: $0) } ?? LocalDays.adding(1, to: newest.validFrom) ?? today
            _form = State(initialValue: WorkModelForm(basedOn: newest, startingOn: max(today, after)))
        } else {
            _form = State(initialValue: WorkModelForm(validFrom: today, timezone: calendar.timeZone.identifier))
        }
    }

    private var outcome: NewVersionOutcome { store.models.checkNewVersion(validFrom: form.validFrom) }
    private var formValid: Bool { if case .success = form.build() { true } else { false } }
    private var overlaps: Bool { if case .overlaps = outcome { true } else { false } }
    private var canSave: Bool { formValid && !overlaps && !saving }
    private var today: LocalDay { calendar.day(for: .now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    Text(wmKey("wm.new.intro")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    consequence
                    WorkModelFormFields(form: $form, calendar: calendar, showsEnd: false, startLabel: wmKey("wm.new.starts"))
                    if let error = store.error {
                        ErrorBanner(message: WorkModelEditSheet.message(error), retryTitle: "common.dismiss") { store.error = nil }
                    }
                    Button { confirming = true } label: { Text(wmKey("wm.new.create")) }
                        .buttonStyle(.ttPrimary)
                        .disabled(!canSave)
                        .accessibilityIdentifier("workmodel.new.create")
                }
                .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(wmKey("wm.new.title")).inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } } }
        }
        .environment(\.timeZone, calendar.timeZone)
        .onAppear { store.error = nil }
        .confirmationDialog(wm("wm.new.confirm_title \(WorkModelCard.display(form.validFrom))"), isPresented: $confirming, titleVisibility: .visible) {
            Button(wm("wm.new.confirm_action")) { Task { await save() } }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text(verbatim: consequenceText)
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 700)
        #endif
    }

    private var consequenceText: String {
        switch outcome {
        case .ok(let predecessor?, let end?):
            wm("wm.new.ends_predecessor \(WorkModelCard.display(predecessor.validFrom)) \(WorkModelCard.display(end))")
        case .ok:
            wm("wm.new.no_predecessor")
        case .overlaps(let newest):
            wm("wm.new.overlap \(WorkModelCard.display(newest.validFrom))")
        }
    }

    @ViewBuilder private var consequence: some View {
        VStack(alignment: .leading, spacing: TT.Space.xs) {
            HStack(alignment: .top, spacing: TT.Space.s) {
                Image(systemName: overlaps ? "exclamationmark.triangle.fill" : "arrow.triangle.branch").foregroundStyle(overlaps ? TT.danger : TT.textSecondary).accessibilityHidden(true)
                Text(verbatim: consequenceText).font(TTFont.label).foregroundStyle(overlaps ? TT.danger : TT.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            if !overlaps && formValid && form.validFrom < today {
                Text(wmKey("wm.new.past")).font(TTFont.meta).foregroundStyle(TT.warning).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(TT.Space.m).frame(maxWidth: .infinity, alignment: .leading)
        .background(TT.surface, in: .rect(cornerRadius: TT.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workmodel.new.consequence")
    }

    private func save() async {
        saving = true
        defer { saving = false }
        if await store.create(form: form) != nil { dismiss() }
    }
}

// MARK: - End a version

/// Sets the last valid day of an open-ended version (e.g. end of the apprenticeship); nothing else changes and the history stays.
struct WorkModelEndSheet: View {
    let store: WorkModelStore
    let version: WorkModel
    let calendar: DayCalendar
    @Environment(\.dismiss) private var dismiss
    @State private var day: LocalDay
    @State private var confirming = false
    @State private var saving = false

    init(store: WorkModelStore, version: WorkModel, calendar: DayCalendar) {
        self.store = store
        self.version = version
        self.calendar = calendar
        _day = State(initialValue: max(version.validFrom, calendar.day(for: .now)))
    }

    private var issue: EndVersionIssue? { store.models.checkEnd(of: version, on: day) }
    private var canEnd: Bool { issue == nil && !saving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    Text(wm("wm.end.intro \(WorkModelCard.range(version))")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    FormSection {
                        EditorRow {
                            DatePicker(wmKey("wm.end.last_day"), selection: dayBinding($day, calendar: calendar), in: PlanFormat.local(version.validFrom, calendar: calendar)..., displayedComponents: .date)
                                .accessibilityIdentifier("workmodel.end.date")
                        }
                    }
                    if let issue {
                        Text(verbatim: Self.message(issue, version: version)).font(TTFont.label).foregroundStyle(TT.danger).accessibilityIdentifier("workmodel.end.issue")
                    } else {
                        Text(wm("wm.end.consequence \(WorkModelCard.display(day))")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                    }
                    if let error = store.error {
                        ErrorBanner(message: WorkModelEditSheet.message(error), retryTitle: "common.dismiss") { store.error = nil }
                    }
                    Button { confirming = true } label: { Text(wmKey("wm.end.action")) }
                        .buttonStyle(.ttDanger)
                        .disabled(!canEnd)
                        .accessibilityIdentifier("workmodel.end.confirm")
                }
                .padding(TT.Space.l).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle(wmKey("wm.end.title")).inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } } }
        }
        .environment(\.timeZone, calendar.timeZone)
        .onAppear { store.error = nil }
        .confirmationDialog(wm("wm.end.confirm_title \(WorkModelCard.display(day))"), isPresented: $confirming, titleVisibility: .visible) {
            Button(wm("wm.end.confirm_action"), role: .destructive) { Task { await save() } }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text(wmKey("wm.end.confirm_message"))
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }

    static func message(_ issue: EndVersionIssue, version: WorkModel) -> String {
        switch issue {
        case .invalidDate: wm("wm.end.invalid")
        case .beforeStart: wm("wm.end.before_start \(WorkModelCard.display(version.validFrom))")
        case .overlapsLater(let later): wm("wm.end.overlaps_later \(WorkModelCard.display(later.validFrom))")
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        if await store.end(version, on: day) != nil { dismiss() }
    }
}

// MARK: - Timeline

/// Vertical rail with a dot per version; `isLast` ends the line.
struct TimelineRail: View {
    let highlighted: Bool
    let isLast: Bool
    @Environment(\.ttTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(highlighted ? theme.accent : TT.textTertiary).frame(width: 12, height: 12).padding(.top, 26)
            if !isLast { Rectangle().fill(TT.separator).frame(width: 2).frame(maxHeight: .infinity) }
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }
}

/// Days between two versions that no work model covers.
struct TimelineGapRow: View {
    let from: LocalDay
    let to: LocalDay

    var body: some View {
        HStack(alignment: .top, spacing: TT.Space.m) {
            VStack(spacing: 0) { Rectangle().fill(TT.separator).frame(width: 2).frame(maxHeight: .infinity) }.frame(width: 12).accessibilityHidden(true)
            HStack(spacing: TT.Space.s) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(TT.warning).accessibilityHidden(true)
                Text(wm("wm.gap \(WorkModelCard.display(from)) \(WorkModelCard.display(to))")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
            .padding(.vertical, TT.Space.s)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workmodel.gap")
        }
    }
}
