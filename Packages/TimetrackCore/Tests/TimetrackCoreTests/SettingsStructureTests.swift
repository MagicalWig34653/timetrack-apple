import Foundation
import Testing
@testable import TimetrackCore

// SET-A: the settings structure mirrors the web app's groups (names, order, entry names).

private func groups(_ platform: SettingsPlatform, off: Set<ModuleKey> = []) -> [SettingsGroup] {
    SettingsStructure.groups(platform: platform, isEnabled: { !off.contains($0) })
}

@Suite("Settings structure")
struct SettingsStructureTests {
    @Test("group names and order match the web app; groups without native entries vanish")
    func groupNamesAndOrder() {
        #expect(groups(.iOS).map(\.title) == [
            "Profil & Sicherheit", "Arbeitszeit & Urlaub", "Orte & Automatik", "Benachrichtigungen & Kalender", "Daten & Export", "Darstellung & Module"
        ])
        #expect(SettingsGroupID.allCases.map(\.title).contains("KI-Zugang"))
        #expect(SettingsGroupID.allCases.map(\.title).last == "Verwaltung (Admin)")
    }

    @Test("every entry belongs to exactly one group and ids are unique")
    func uniqueEntries() {
        let ids = SettingsStructure.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(SettingsEntryID.allCases))
        #expect(SettingsStructure.all.allSatisfy { !$0.description.isEmpty && !$0.title.isEmpty })
    }

    @Test("account group order follows the web app")
    func accountOrder() {
        let account = groups(.iOS).first { $0.id == .account }
        #expect(account?.entries.map(\.title) == ["Profil", "Passkeys", "Verknüpfte Anmeldungen", "Wiederherstellung", "Sitzungen"])
    }

    @Test("a switched-off module hides its entries and empties groups")
    func moduleVisibility() {
        let titles = groups(.iOS, off: [.planning, .automation, .reports, .transfer]).flatMap(\.entries).map(\.title)
        for hidden in ["Freigaben", "Urlaubsanspruch", "Urlaubserinnerungen", "Lernfelder", "Orte", "Auslöse-Links", "Fokus-Filter", "Export"] {
            #expect(!titles.contains(hidden))
        }
        #expect(!groups(.iOS, off: [.automation]).contains { $0.id == .places })
        #expect(titles.contains("Arbeitsmodell"))
    }

    @Test("platform filter: Mac-only and phone-only entries")
    func platforms() {
        let phone = groups(.iOS).flatMap(\.entries).map(\.title)
        let mac = groups(.macOS).flatMap(\.entries).map(\.title)
        #expect(phone.contains("Apple Watch") && !mac.contains("Apple Watch"))
        #expect(mac.contains("Menüleiste") && !phone.contains("Menüleiste"))
    }

    @Test("SET-B: the Mac shows the same Arbeit/Hinweise/Daten entries as iOS; only Watch and Mac-only pages differ")
    func macParity() {
        let phone = Set(groups(.iOS).flatMap(\.entries).map(\.id))
        let mac = Set(groups(.macOS).flatMap(\.entries).map(\.id))
        for id in [SettingsEntryID.vacationEntitlement, .vacationReminders, .overworkHints, .focusFilter, .export, .cancelled] {
            #expect(phone.contains(id) && mac.contains(id), "\(id) must exist on both platforms")
        }
        #expect(phone.subtracting(mac) == [.appleWatch])
        #expect(mac.subtracting(phone) == [.menuBar, .activity])
    }

    @Test("SET-B: the Mac hides module-bound entries like iOS")
    func macModuleVisibility() {
        let titles = groups(.macOS, off: [.planning, .automation, .transfer]).flatMap(\.entries).map(\.title)
        for hidden in ["Urlaubsanspruch", "Urlaubserinnerungen", "Fokus-Filter", "Export"] { #expect(!titles.contains(hidden)) }
        #expect(titles.contains("Überstunden-Hinweise") && titles.contains("Stornierte Einträge"))
    }

    @Test("search matches title and keywords, all words required")
    func search() {
        let found = SettingsStructure.groups(platform: .iOS, isEnabled: { _ in true }, query: "ics apple").flatMap(\.entries).map(\.title)
        #expect(found == ["Kalender-Abos"])
        #expect(SettingsStructure.groups(platform: .iOS, isEnabled: { _ in true }, query: "gibtsnicht").isEmpty)
    }
}
