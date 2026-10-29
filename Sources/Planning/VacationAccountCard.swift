import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// U3: calm summary of the vacation account: one big figure (days left), one segmented bar (taken / approved / requested / planned / free)
/// with a legend, then carry-over and expiry hint. Replaces the ring card; all numbers come from the backend balance.
struct VacationAccountBreakdown: Equatable {
    var taken: Int
    var approved: Int
    var requested: Int
    var planned: Int
    var free: Int
    var capacity: Int { taken + approved + requested + planned + max(free, 0) }

    /// Splits the booked and planned half days of the balance by status using the year's vacation absences (the balance has no split).
    init(_ balance: VacationBalance, absences: [Absence]) {
        let year = String(balance.year)
        let vacation = absences.filter { $0.kind == .vacation && $0.startDate.hasPrefix(year) }
        func sum(_ status: AbsenceStatus) -> Int { vacation.filter { $0.status == status }.reduce(0) { $0 + $1.countedHalfDays } }
        let booked = max(balance.bookedHalfDays, 0), plannedAll = max(balance.plannedHalfDays, 0)
        var takenPart = min(sum(.taken), booked)
        var requestedPart = min(sum(.requested), plannedAll)
        if vacation.isEmpty { takenPart = 0; requestedPart = 0 }
        taken = takenPart
        approved = booked - takenPart
        requested = requestedPart
        planned = plannedAll - requestedPart
        free = balance.availableAfterPlannedHalfDays
    }
}

struct VacationAccountCard: View {
    let balance: VacationBalance
    let absences: [Absence]
    let settings: VacationSettings?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var parts: VacationAccountBreakdown { VacationAccountBreakdown(balance, absences: absences) }
    private var over: Bool { balance.availableAfterPlannedHalfDays < 0 }

    var body: some View {
        let parts = parts
        VStack(alignment: .leading, spacing: TT.Space.s) {
            SectionHeader("vacation.balance")
            Card {
                VStack(alignment: .leading, spacing: TT.Space.l) {
                    VStack(alignment: .leading, spacing: TT.Space.xs) {
                        u3("u3.vac.left").font(TTFont.label).foregroundStyle(TT.textSecondary)
                        Text("vacation.days \(HalfDayFormat.days(balance.availableHalfDays))")
                            .font(.system(size: 52, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                            .monospacedDigit().foregroundStyle(TT.textPrimary)
                            .accessibilityIdentifier("vacation.available.value")
                        u3("u3.vac.after_planned \(HalfDayFormat.days(balance.availableAfterPlannedHalfDays))")
                            .font(TTFont.meta).foregroundStyle(over ? TT.danger : TT.textSecondary)
                    }
                    bar(parts)
                    legend(parts)
                    Divider()
                    facts
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("vacation.account")
            }
        }
    }

    private func tint(_ id: String) -> Color {
        switch id {
        case "taken": TT.kindVacation
        case "approved": TT.kindVacation.opacity(0.55)
        case "requested": Color.blue
        case "planned": TT.warning
        default: TT.kindVacation.opacity(0.14)
        }
    }

    private func segments(_ p: VacationAccountBreakdown) -> [(id: String, title: String, halfDays: Int)] {
        [("taken", u3String("u3.vac.taken"), p.taken), ("approved", u3String("u3.vac.approved"), p.approved),
         ("requested", u3String("u3.vac.requested"), p.requested), ("planned", u3String("u3.vac.planned"), p.planned),
         ("free", u3String("u3.vac.free"), max(p.free, 0))]
    }

    private func bar(_ p: VacationAccountBreakdown) -> some View {
        let all = segments(p)
        let total = max(p.capacity, 1)
        return GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(all.filter { $0.halfDays > 0 }, id: \.id) { segment in
                    RoundedRectangle(cornerRadius: 4).fill(tint(segment.id))
                        .frame(width: max(4, (proxy.size.width - 8) * CGFloat(segment.halfDays) / CGFloat(total)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 14)
        .clipShape(.rect(cornerRadius: 7))
        .accessibilityHidden(true)
    }

    private func legend(_ p: VacationAccountBreakdown) -> some View {
        VStack(alignment: .leading, spacing: TT.Space.xs) {
            ForEach(segments(p).filter { $0.halfDays > 0 || $0.id == "free" }, id: \.id) { segment in
                HStack(spacing: TT.Space.s) {
                    Circle().fill(tint(segment.id)).frame(width: 10, height: 10).accessibilityHidden(true)
                    Text(verbatim: segment.title).foregroundStyle(TT.textPrimary)
                    Spacer(minLength: TT.Space.s)
                    Text("vacation.days \(HalfDayFormat.days(segment.halfDays))").monospacedDigit().foregroundStyle(TT.textSecondary)
                }
                .font(TTFont.meta)
            }
            if over {
                Label { u3("u3.vac.over \(HalfDayFormat.days(-balance.availableAfterPlannedHalfDays))") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(TTFont.meta).foregroundStyle(TT.danger)
            }
        }
    }

    @ViewBuilder private var facts: some View {
        VStack(alignment: .leading, spacing: TT.Space.xs) {
            fact("u3.vac.entitlement", balance.entitlementHalfDays)
            if balance.carryOverHalfDays != 0 { fact("u3.vac.carry", balance.carryOverHalfDays) }
            if balance.adjustmentHalfDays != 0 { fact("u3.vac.adjust", balance.adjustmentHalfDays) }
            if balance.carryOverHalfDays > 0, let expiry = settings?.carryOverExpiry {
                Label { u3("u3.vac.expiry \(Self.displayExpiry(expiry))") } icon: { Image(systemName: "hourglass") }
                    .font(TTFont.meta).foregroundStyle(TT.textSecondary)
            }
        }
    }

    private func fact(_ key: String.LocalizationValue, _ halfDays: Int) -> some View {
        HStack {
            u3(key).foregroundStyle(TT.textSecondary)
            Spacer()
            Text("vacation.days \(HalfDayFormat.days(halfDays))").monospacedDigit().foregroundStyle(TT.textPrimary)
        }
        .font(TTFont.meta)
    }

    /// `MM-DD` to "31.03."
    static func displayExpiry(_ mmdd: String) -> String {
        let parts = mmdd.split(separator: "-")
        return parts.count == 2 ? "\(parts[1]).\(parts[0])." : mmdd
    }
}
