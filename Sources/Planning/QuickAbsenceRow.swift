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
                HStack(spacing: TT.Space.s) {
                    ForEach([AbsenceKind.sick, .vacation], id: \.self) { kind in
                        Button { request = AbsenceRequest(kind: kind, start: today, end: today) } label: { Label(kind.actionKey, systemImage: kind.ttSymbol).frame(maxWidth: .infinity) }
                            .buttonStyle(.ttSecondary).accessibilityIdentifier("today.quick.\(kind.rawValue)")
                    }
                    Menu {
                        AbsenceQuickMenuItems(start: today, end: today) { request = $0 }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 36, height: 36) }
                        .accessibilityLabel(Text("plan.add")).accessibilityIdentifier("today.quick.more")
                }
            }
            .absenceEditor($request, actions: AbsenceEditorActions(planning: store))
        }
    }
}
