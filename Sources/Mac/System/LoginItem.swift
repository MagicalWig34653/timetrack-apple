import Foundation
import Observation
import ServiceManagement

/// M2: "Beim Anmelden starten" through `SMAppService.mainApp`. The user can also remove the item in System Settings > General >
/// Login Items, so the state is always read from the system, never remembered.
@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var lastError: String?

    var isOn: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Der Anmeldeeintrag konnte nicht geändert werden: \(error.localizedDescription)"
        }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
