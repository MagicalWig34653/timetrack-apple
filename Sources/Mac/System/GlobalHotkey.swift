import AppKit
import Carbon.HIToolbox

/// M2: one global hotkey through Carbon's `RegisterEventHotKey`. It is a public API, needs no Accessibility or Input Monitoring
/// permission and works in the App Sandbox. It does not read other keystrokes: the system only reports this one key combination.
@MainActor
final class GlobalHotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var registeredPreset: HotkeyPreset?
    /// Set false when the system refused the combination (already taken by another app).
    private(set) var lastRegistrationFailed = false
    var onPress: (@MainActor () -> Void)?

    private static let signature: OSType = 0x54544B31 // 'TTK1'

    func register(_ preset: HotkeyPreset?) {
        guard preset != registeredPreset || (preset != nil && reference == nil) else { return }
        unregister()
        lastRegistrationFailed = false
        guard let preset else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            reference = ref
            registeredPreset = preset
        } else {
            lastRegistrationFailed = true
        }
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        registeredPreset = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon calls this on the main thread; hop explicitly so the Swift 6 isolation check is satisfied.
            DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotkeyRelay.fire() } }
            return noErr
        }, 1, &spec, nil, &handler)
        if status == noErr { GlobalHotkeyRelay.target = self }
    }
}

/// The C callback cannot capture; it reaches the hotkey through this relay.
@MainActor
enum GlobalHotkeyRelay {
    static weak var target: GlobalHotkey?
    static func fire() { target?.onPress?() }
}
