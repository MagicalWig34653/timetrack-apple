import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// The figures of the vacation account as tiles (entitlement, carry-over, corrections, taken, planned) with a one-tap edit of the
/// yearly entitlement, like the PWA's balance card. With a snapshot the contract reports entitlement and carry-over as 0; the stored
/// settings are shown instead (marked as replaced).
struct VacationFigures: View {
    let store: PlanningStore
    let balance: VacationBalance
    @State private var editing = false

    private var snapshot: Bool { balance.snapshotDate != nil }
    private var entitlement: Int { snapshot ? (store.settings?.annualEntitlementHalfDays ?? 0) : balance.entitlementHalfDays }
    private var carryOver: Int { snapshot ? (store.settings?.carryOverByYear?[String(balance.year)] ?? 0) : balance.carryOverHalfDays }

    var body: some View {
        VStack(alignment: .leading, spacing: TT.Space.s) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: TT.Space.s)], spacing: TT.Space.s) {
                tile("vacation.entitlement", entitlement, note: snapshot ? "vacation.tile_replaced" : "vacation.tile_entitlement", id: "entitlement")
                tile("vacation.carry_over", carryOver, note: snapshot ? "vacation.tile_replaced" : "vacation.tile_carry_text", id: "carry")
                tile("vacation.adjustment", balance.adjustmentHalfDays, note: "vacation.tile_adjustments", signed: true, id: "adjustments")
                if let date = balance.snapshotDate, let rest = balance.snapshotRemainingHalfDays {
                    tile("vacation.tile_snapshot", rest, note: "vacation.tile_snapshot_text \(PlanFormat.shortDay(date, calendar: store.calendar))", id: "snapshot")
                }
                tile("vacation.booked", balance.bookedHalfDays, note: "vacation.tile_booked_text", id: "booked")
                tile("vacation.planned", balance.plannedHalfDays, note: "vacation.tile_planned_text", id: "planned")
            }
            Button { editing = true } label: { Label("vacation.edit_entitlement", systemImage: "pencil") }
                .buttonStyle(.ttSecondary)
                .accessibilityIdentifier("vacation.edit_entitlement")
            Text("vacation.balance_formula").font(TTFont.meta).foregroundStyle(TT.textSecondary).padding(.horizontal, TT.Space.xs)
        }
        .sheet(isPresented: $editing) { EntitlementSheet(store: store) }
    }

    private func tile(_ title: LocalizedStringKey, _ halfDays: Int, note: LocalizedStringKey, signed: Bool = false, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(TTFont.meta).foregroundStyle(TT.textSecondary).lineLimit(2)
            Text("vacation.days \(signed && halfDays > 0 ? "+" : "")\(HalfDayFormat.days(halfDays))")
                .font(TTFont.stat).foregroundStyle(TT.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityIdentifier("vacation.tile.\(id)")
            Text(note).font(TTFont.eyebrow).foregroundStyle(TT.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(TT.Space.m).frame(maxWidth: .infinity, alignment: .leading)
        .ttSurface(radius: TT.Radius.control)
        .accessibilityElement(children: .combine)
    }
}

/// Edits only the yearly entitlement; region, carry-over and expiry stay as saved.
private struct EntitlementSheet: View {
    let store: PlanningStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var invalid = false
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    FormSection("vacation.entitlement_field", footer: "vacation.entitlement_hint") {
                        TextField("vacation.entitlement_field", text: $text).padding(TT.Space.l).accessibilityIdentifier("vacation.entitlement.field")
                    }
                    if invalid { HintBanner("vacation.error_days", symbol: "exclamationmark.triangle.fill") }
                    if let error = store.error { ErrorBanner(message: error.germanDescription, retryTitle: "common.dismiss") { store.error = nil } }
                    Button("vacation.settings_save") { Task { await save() } }.buttonStyle(.ttPrimary).disabled(saving).accessibilityIdentifier("vacation.entitlement.save")
                }
                .padding(TT.Space.l).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .ttScreenBackground()
            .navigationTitle("vacation.edit_entitlement").inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } } }
        }
        .onAppear {
            store.error = nil
            text = HalfDayFormat.days(store.settings?.annualEntitlementHalfDays ?? store.balance?.entitlementHalfDays ?? 60)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #endif
        .presentationDetents([.medium])
    }

    private func save() async {
        guard let half = HalfDayFormat.parseHalfDays(text), half >= 0 else { invalid = true; return }
        invalid = false
        saving = true
        defer { saving = false }
        var settings = store.settings ?? VacationSettings()
        settings.annualEntitlementHalfDays = half
        if await store.saveSettings(settings) { dismiss() }
    }
}
