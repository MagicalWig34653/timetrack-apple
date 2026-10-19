import SwiftUI
import TimetrackCore
import TimetrackStores

/// Commands the "Zeit" screen reacts to (menu bar, keyboard shortcuts, toolbar of other screens).
enum TimeCommand { case previousWeek, nextWeek, thisWeek, newEntry, search, toggleInspector }

/// Menu bar of the Mac app: File/Edit additions, "Zeit" menu, "Gehe zu" menu. Every command has a keyboard shortcut.
struct TimetrackCommands: Commands {
    let model: AppModel
    let ui: UIState

    private var signedIn: Bool { model.phase == .signedIn }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(AD.s("command.new_entry_ellipsis")) { ui.send(.newEntry) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!signedIn)
        }
        CommandGroup(after: .textEditing) {
            Button(AD.s("command.search")) { ui.send(.search) }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!signedIn)
        }
        CommandMenu("menu.time") {
            Button(model.today?.running == nil ? "command.start" : "command.stop") {
                Task { @MainActor in await toggleTimer(model) }
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(model.today == nil)

            Divider()

            Button("time.previous_week") { ui.send(.previousWeek) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!signedIn)
            Button("time.next_week") { ui.send(.nextWeek) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!signedIn)
            Button("time.this_week") { ui.send(.thisWeek) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!signedIn)

            Divider()

            Button("command.reload") {
                Task { @MainActor in
                    await model.today?.load()
                    await model.timeList?.load()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!signedIn)
        }
        CommandMenu(AD.s("menu.goto")) {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.titleKey) { ui.selection = item }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(!signedIn || !(item.requiredModule.map(model.isEnabled) ?? true))
            }
        }
        CommandGroup(after: .sidebar) {
            Button(AD.s("command.inspector")) { ui.send(.toggleInspector) }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(!signedIn)
        }
    }
}

@MainActor
func toggleTimer(_ model: AppModel) async {
    guard let today = model.today else { return }
    if today.running == nil { await today.start() } else { await today.stop() }
}
