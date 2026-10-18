import SwiftUI
import TimetrackCore
import TimetrackDesign
import TimetrackStores

/// Compact "Urlaub eintragen / Krank melden" actions for the Heute tab (module `planning`). Hidden when the module is off.
struct QuickAbsenceRow: View {
    @Environment(AppModel.self) private var model
    @State private var request: AbsenceRequest?

    var body: some View {
        if let store = model.planning {
            let today = store.today
            Card(padding: TT.Space.m) {
                // Icon + title in one row if it fits, then title only, then one full-width button per row (never a wrapped label).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: TT.Space.s) { buttons(today: today, withIcon: true, measured: true); more(today: today) }
                    HStack(spacing: TT.Space.s) { buttons(today: today, withIcon: false, measured: true); more(today: today) }
                    VStack(spacing: TT.Space.s) { buttons(today: today, withIcon: true, measured: false); more(today: today) }
                }
            }
            .absenceEditor($request, actions: AbsenceEditorActions(planning: store))
        }
    }

    @ViewBuilder private func buttons(today: LocalDay, withIcon: Bool, measured: Bool) -> some View {
        ForEach([AbsenceKind.sick, .vacation], id: \.self) { kind in
            Button { request = AbsenceRequest(kind: kind, start: today, end: today) } label: {
                Group { if withIcon { Label(kind.actionKey, systemImage: kind.ttSymbol) } else { Text(kind.actionKey) } }
                    .fixedSize(horizontal: measured, vertical: false)
            }
            .buttonStyle(.ttSecondary).accessibilityIdentifier("today.quick.\(kind.rawValue)")
        }
    }

    private func more(today: LocalDay) -> some View {
        Menu {
            AbsenceQuickMenuItems(start: today, end: today) { request = $0 }
        } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44).contentShape(.rect) }
            .accessibilityLabel(Text("plan.add")).accessibilityIdentifier("today.quick.more")
    }
}
