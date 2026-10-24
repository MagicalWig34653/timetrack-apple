import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// "Zeitkonto": the balance with its opening balance and the sum of manual corrections, plus booking of an opening balance and dated corrections
/// with a reason (PWA: Einstellungen › Zeitkonto). The contract has no list or delete endpoint for adjustments, so a booking can only be
/// balanced by a counter-booking; the screen says so before it books.
struct TimeAccountScreen: View {
    @Environment(AppModel.self) private var model
    @State private var store: TimeAccountStore?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TT.Space.l) {
                Text(wmKey("wm.account.intro")).font(TTFont.meta).foregroundStyle(TT.textSecondary)
                if let store {
                    if let error = store.error, !store.isSaving {
                        ErrorBanner(message: error.germanDescription, retryTitle: "common.retry") { Task { await store.load() } }
                    }
                    if let account = store.account {
                        BalanceCard(account: account)
                        if store.canSetOpening {
                            AdjustmentForm(store: store, kind: .opening, calendar: model.dayCalendar)
                        }
                        AdjustmentForm(store: store, kind: .correction, calendar: model.dayCalendar)
                    } else if store.isLoading {
                        SkeletonList(rows: 3)
                    }
                } else {
                    SkeletonList(rows: 3)
                }
            }
            .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .ttScreenBackground()
        .navigationTitle(wmKey("wm.account.title"))
        .task {
            if store == nil, let client = model.apiClient {
                let created = TimeAccountStore(client: client)
                created.onOutcome = { TTHaptics.handle($0) }
                created.onSaved = { Task { await model.today?.load() } }
                store = created
            }
            await store?.load()
        }
    }
}

private struct BalanceCard: View {
    let account: TimeAccount

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: TT.Space.m) {
                Eyebrow(wmKey("wm.account.balance"))
                HStack(alignment: .firstTextBaseline, spacing: TT.Space.s) {
                    Text(verbatim: DurationFormat.signed(account.balanceSeconds).replacingOccurrences(of: "-", with: "−"))
                        .font(TTFont.stat).foregroundStyle(account.balanceSeconds < 0 ? TT.danger : TT.textPrimary)
                        .accessibilityIdentifier("account.balance")
                    if account.provisional { StatusChip(verbatim: wm("wm.account.provisional"), tone: .neutral) }
                }
                Text(account.accountStart.map { wm("wm.account.since \(WorkModelCard.display($0))") } ?? wm("wm.account.no_start"))
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
                VStack(spacing: 0) {
                    FormRow(wmKey("wm.account.opening")) { Text(verbatim: DurationFormat.signed(account.openingSeconds)).monospacedDigit() }.padding(.vertical, 2)
                    FormRow(wmKey("wm.account.corrections")) { Text(verbatim: DurationFormat.signed(account.adjustmentSeconds)).monospacedDigit() }.padding(.vertical, 2)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One booking form: opening balance (date, value, reason) or correction (date, credit or deduction, reason); a confirmation precedes the booking.
private struct AdjustmentForm: View {
    let store: TimeAccountStore
    let kind: AccountAdjustmentInput.Kind
    let calendar: DayCalendar
    @State private var date: LocalDay
    @State private var deduct = false
    @State private var amount = ""
    @State private var reason: String
    @State private var showErrors = false
    @State private var confirming = false
    @State private var notice: String?

    init(store: TimeAccountStore, kind: AccountAdjustmentInput.Kind, calendar: DayCalendar) {
        self.store = store
        self.kind = kind
        self.calendar = calendar
        _date = State(initialValue: calendar.day(for: .now))
        _reason = State(initialValue: kind == .opening ? wm("wm.account.opening_reason") : "")
    }

    private var prefix: String { kind == .opening ? "account.opening" : "account.correction" }

    /// The signed value as the core form wants it; opening balances may be negative too (typed with a minus).
    private var form: AccountAdjustmentForm {
        let text = amount.trimmingCharacters(in: .whitespaces)
        let signed = kind == .correction && deduct && !text.hasPrefix("-") && !text.hasPrefix("+") ? "-\(text)" : text
        return AccountAdjustmentForm(kind: kind, date: date, value: signed, reason: reason)
    }

    private var errors: Set<AccountAdjustmentForm.Field> {
        if case .failure(let failure) = form.build() { return failure.fields }
        return []
    }

    var body: some View {
        FormSection(kind == .opening ? wmKey("wm.account.opening_title") : wmKey("wm.account.correction_title"),
                    footer: kind == .opening ? wmKey("wm.account.opening_hint") : wmKey("wm.account.correction_hint")) {
            EditorRow { DatePicker(kind == .opening ? wmKey("wm.account.start_date") : wmKey("wm.account.date"), selection: dayBinding($date, calendar: calendar), displayedComponents: .date).accessibilityIdentifier("\(prefix).date") }
            if kind == .correction {
                EditorRow {
                    Picker(wmKey("wm.account.direction"), selection: $deduct) {
                        Text(wmKey("wm.account.credit")).tag(false)
                        Text(wmKey("wm.account.deduction")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("\(prefix).direction")
                }
            }
            field(kind == .opening ? wmKey("wm.account.opening_value") : wmKey("wm.account.amount"), $amount, .value, hint: wmKey("wm.account.value_hint"), id: "\(prefix).value")
            field(wmKey("wm.account.reason"), $reason, .reason, hint: nil, id: "\(prefix).reason")
            if let notice { Text(verbatim: notice).font(TTFont.meta).foregroundStyle(TT.success).padding(.horizontal, TT.Space.l).accessibilityIdentifier("\(prefix).saved") }
            Button { showErrors = true; if errors.isEmpty { confirming = true } } label: {
                Text(kind == .opening ? wmKey("wm.account.opening_save") : wmKey("wm.account.correction_save"))
            }
            .buttonStyle(.ttPrimary).disabled(store.isSaving).padding(TT.Space.l)
            .accessibilityIdentifier("\(prefix).save")
        }
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(wm("wm.account.confirm_action")) { Task { await book() } }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text(wmKey(kind == .opening ? "wm.account.opening_confirm_message" : "wm.account.confirm_message"))
        }
    }

    private var confirmTitle: String {
        let value = DurationFormat.parse(form.value).map { DurationFormat.signed($0).replacingOccurrences(of: "-", with: "−") } ?? ""
        return kind == .opening ? wm("wm.account.opening_confirm \(value) \(WorkModelCard.display(date))") : wm("wm.account.confirm \(value) \(WorkModelCard.display(date))")
    }

    private func field(_ key: LocalizedStringKey, _ text: Binding<String>, _ field: AccountAdjustmentForm.Field, hint: LocalizedStringKey?, id: String) -> some View {
        let bad = showErrors && errors.contains(field)
        return VStack(alignment: .leading, spacing: 4) {
            Text(key).font(TTFont.meta).foregroundStyle(bad ? TT.danger : TT.textSecondary)
            TextField(key, text: text)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(field == .reason ? .sentences : .never)
                #endif
                .accessibilityIdentifier(id)
            if bad { Text(field == .reason ? wmKey("wm.account.invalid_reason") : wmKey("wm.account.invalid_value")).font(TTFont.meta).foregroundStyle(TT.danger) }
            else if let hint { Text(hint).font(TTFont.meta).foregroundStyle(TT.textTertiary) }
        }
        .padding(.horizontal, TT.Space.l).padding(.vertical, TT.Space.s)
    }

    private func book() async {
        if await store.book(form) {
            notice = kind == .opening ? wm("wm.account.opening_saved") : wm("wm.account.correction_saved")
            if kind == .correction { amount = ""; reason = "" }
            showErrors = false
        } else {
            notice = nil
        }
    }
}
