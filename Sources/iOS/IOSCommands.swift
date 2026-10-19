import SwiftUI
import TimetrackCore
import TimetrackStores

/// AD1: strings of the adaptive shell in their own table (`AD1.xcstrings`), so parallel packages editing `Localizable.xcstrings` do not conflict.
enum IPadStrings {
    static func s(_ key: String.LocalizationValue) -> String { String(localized: key, table: "AD1") }
}

/// AD1: menu bar commands of iPadOS (visible with the ⌘ key held and in the menu bar of Stage Manager / external display).
struct IOSCommands: Commands {
    let model: AppModel
    let ui: UIState

    private var signedIn: Bool { model.phase == .signedIn }

    var body: some Commands {
        CommandMenu(IPadStrings.s("menu.time")) {
            Button(model.today?.running == nil ? IPadStrings.s("command.start") : IPadStrings.s("command.stop")) {
                Task { @MainActor in
                    guard let today = model.today else { return }
                    if today.running == nil { await today.start() } else { await today.stop() }
                }
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(model.today == nil)
            Button(IPadStrings.s("command.reload")) {
                Task { @MainActor in
                    await model.today?.load()
                    await model.timeList?.load()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!signedIn)
        }
        CommandMenu(IPadStrings.s("menu.goto")) {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.titleKey) { ui.selection = section }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(!signedIn || !(section.requiredModule.map(model.isEnabled) ?? true))
            }
        }
    }
}
