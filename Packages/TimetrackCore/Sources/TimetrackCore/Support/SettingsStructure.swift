import Foundation

/// SET-A: the structure of the settings, mirroring the web app's `nav.ts` (SETTINGS_GROUPS, SETTINGS_DESCRIPTIONS, SETTINGS_KEYWORDS).
/// Same eight group ids, names and order; only entries that exist natively are listed (the web-only ones, such as the AI access
/// and the admin pages, are left out, so those groups never appear). Entries without a web counterpart are marked `webPath == nil`.
public enum SettingsPlatform: Sendable { case iOS, macOS }

public enum SettingsGroupID: String, CaseIterable, Sendable {
    case account, work, places, notify, ai, data, app, admin

    /// Same names as the web app (`nav.settings_group.*`).
    public var title: String {
        switch self {
        case .account: "Profil & Sicherheit"
        case .work: "Arbeitszeit & Urlaub"
        case .places: "Orte & Automatik"
        case .notify: "Benachrichtigungen & Kalender"
        case .ai: "KI-Zugang"
        case .data: "Daten & Export"
        case .app: "Darstellung & Module"
        case .admin: "Verwaltung (Admin)"
        }
    }
}

public enum SettingsEntryID: String, CaseIterable, Sendable {
    // account
    case profile, passkeys, identities, recovery, sessions
    // work
    case workModel, accountTime, vacationEntitlement, learningFields, sharing
    // places
    case places, triggerLinks, focusFilter
    // notify
    case notifications, vacationReminders, overworkHints, calendarFeeds, deviceCalendar
    // data
    case export, cancelled
    // app
    case appearance, modules, menuBar, activity, appleWatch, about
}

public struct SettingsEntry: Sendable, Equatable, Identifiable {
    public let id: SettingsEntryID
    public let group: SettingsGroupID
    public let title: String
    public let description: String
    /// The web app's route of this page (nil for entries that only exist in the native apps).
    public let webPath: String?
    /// The server module that has to be on for the entry to show (the web app's `moduleOfPath`, or the native feature's module).
    public let module: ModuleKey?
    public let platforms: Set<SettingsPlatform>
    /// Extra search words (German), as in the web app's `SETTINGS_KEYWORDS`.
    public let keywords: String
    public let symbol: String
}

public struct SettingsGroup: Sendable, Equatable, Identifiable {
    public let id: SettingsGroupID
    public let entries: [SettingsEntry]
    public var title: String { id.title }
    public init(id: SettingsGroupID, entries: [SettingsEntry]) {
        self.id = id
        self.entries = entries
    }
}

public enum SettingsStructure {
    private static let both: Set<SettingsPlatform> = [.iOS, .macOS]
    private static let phone: Set<SettingsPlatform> = [.iOS]
    private static let mac: Set<SettingsPlatform> = [.macOS]

    private static func e(_ id: SettingsEntryID, _ group: SettingsGroupID, _ title: String, _ symbol: String, _ description: String, web: String? = nil,
                          module: ModuleKey? = nil, on platforms: Set<SettingsPlatform>? = nil, keywords: String = "") -> SettingsEntry {
        SettingsEntry(id: id, group: group, title: title, description: description, webPath: web, module: module, platforms: platforms ?? both,
                      keywords: keywords, symbol: symbol)
    }

    /// Every native entry in display order (the order inside a group follows the web app's `hrefs`; native-only entries follow their neighbours).
    public static let all: [SettingsEntry] = [
        e(.profile, .account, "Profil", "person.crop.circle", "Name, E-Mail-Adresse und Einrichtung deines Kontos.", web: "/settings/profile",
          keywords: "profil name anzeigename e-mail adresse konto einrichtung wiederholen onboarding"),
        e(.passkeys, .account, "Passkeys", "person.badge.key", "Mit diesen Passkeys kannst du dich anmelden. Du kannst mehrere pro Konto haben.", web: "/settings/passkeys",
          keywords: "passkey anmeldung sicherheit konto"),
        e(.identities, .account, "Verknüpfte Anmeldungen", "link", "Externe Konten (OpenID Connect), mit denen du dich zusätzlich anmelden kannst. Passkeys bleiben die empfohlene Anmeldung.",
          web: "/settings/identities", keywords: "openid oidc anmeldung verknüpft"),
        e(.recovery, .account, "Wiederherstellung", "lifepreserver", "Lege fest, wie du dein Konto zurückbekommst, wenn alle Passkeys verloren sind.", web: "/settings/recovery",
          keywords: "wiederherstellung recovery codes passwort"),
        e(.sessions, .account, "Sitzungen", "iphone.and.arrow.forward", "Verwalte, auf welchen Geräten du angemeldet bist.", web: "/settings/sessions",
          keywords: "sitzungen abmelden geräte sicherheit"),

        e(.workModel, .work, "Arbeitsmodell", "calendar.badge.clock", "Soll, Rundung, Schule und feste Pausen. Ändere ab einem Stichtag (neue Version) oder korrigiere eine Version, wenn ein Wert falsch war.",
          web: "/settings/work-model", keywords: "arbeitszeit soll woche tag pause rundung schule fahrtzeit modell firmentage betriebsferien"),
        e(.accountTime, .work, "Zeitkonto", "plusminus.circle", "Anfangsstand und Korrekturen des Zeitkontos. Der Saldo ergibt sich aus den bewerteten Tagen.", web: "/settings/account-time",
          keywords: "zeitkonto saldo anfangsstand korrektur"),
        e(.vacationEntitlement, .work, "Urlaubsanspruch", "beach.umbrella", "Urlaubstage, Region, Übertrag und Saldo-Einträge.", module: .planning, on: phone,
          keywords: "urlaub urlaubsanspruch resturlaub übertrag region"),
        e(.learningFields, .work, "Lernfelder", "list.number", "Deine Liste von Lernfeldern für das Berichtsheft. Du kannst beim Eintragen auch einen anderen Namen tippen.", web: "/settings/learning-fields",
          module: .reports, keywords: "lernfelder berichtsheft ihk"),
        e(.sharing, .work, "Freigaben", "person.2", "Lege fest, wer welche Teile deines Plans sehen darf. Standardmäßig ist alles privat.", web: "/settings/sharing", module: .planning,
          keywords: "freigaben teilen plan privat"),

        e(.places, .places, "Orte", "mappin.and.ellipse", "Orte für den Timer und für die Automatik per Kurzbefehl.", web: "/settings/places", module: .automation,
          keywords: "orte standort ort automatik geofence regeln"),
        e(.triggerLinks, .places, "Auslöse-Links", "link.badge.plus", "Adressen, die beim Öffnen die Zeiterfassung starten oder stoppen, etwa für Widgets, NFC-Tags oder Kurzbefehle ohne Anmeldung.",
          web: "/settings/trigger-links", module: .automation, keywords: "auslöse links url start stopp timer schaltfläche widget kurzbefehl"),
        e(.focusFilter, .places, "Fokus-Filter", "moon.circle", "Timer automatisch mit einem iOS-Fokus starten und stoppen.", module: .automation, on: phone,
          keywords: "fokus filter automatik timer"),

        e(.notifications, .notify, "Hinweise & Push", "bell.badge.waveform", "Lege fest, worüber Timetrack dich informiert. Zeiterfassung und Hinweise in der App funktionieren unabhängig von Push.",
          web: "/settings/notifications", keywords: "hinweise push benachrichtigung erinnerung apns web-push"),
        e(.vacationReminders, .notify, "Urlaubserinnerungen", "bell.badge", "Erinnerung vor geplantem Urlaub, der noch nicht beantragt ist.", module: .planning, on: phone,
          keywords: "urlaub erinnerung antrag hinweis"),
        e(.overworkHints, .notify, "Überstunden-Hinweise", "clock.badge.exclamationmark", "Hinweise bei laufender Zeiterfassung: geplantes Ende, Tagesgrenzen und fehlende Pause.", on: phone,
          keywords: "überstunden hinweise pause tagesgrenze ende"),
        e(.calendarFeeds, .notify, "Kalender-Abos", "calendar.badge.plus", "Abonniere deine Abwesenheiten, Feiertage und Planung in Apple Kalender, Google Kalender oder Outlook.", web: "/settings/calendar-feeds",
          keywords: "kalender abo ics abonnieren apple google outlook feed link url"),
        e(.deviceCalendar, .notify, "Kalender", "calendar", "Kalender dieses Geräts anzeigen oder beschreiben. Termine verlassen das Gerät nie.",
          keywords: "kalender gerät termine eventkit lesen schreiben"),

        e(.export, .data, "Export", "square.and.arrow.up", "Exportiere deine Arbeitszeiten für einen Zeitraum als Tabelle oder PDF, zum Beispiel als Nachweis. Öffnet die Web-App.", web: "/export",
          module: .transfer, on: phone, keywords: "export exportieren csv pdf tabelle nachweis herunterladen"),
        e(.cancelled, .data, "Stornierte Einträge", "trash", "Hier liegen stornierte Zeiteinträge. Du kannst sie wiederherstellen oder endgültig löschen.", web: "/time/cancelled", on: phone,
          keywords: "storniert stornierte einträge papierkorb gelöscht wiederherstellen"),

        e(.appearance, .app, "Darstellung", "paintpalette", "Farbschema und Akzentfarbe gehören zu deinem Konto und gelten auf allen Geräten.", web: "/settings/appearance",
          keywords: "darstellung hell dunkel akzent farbe theme transparenz design haptik symbol"),
        e(.modules, .app, "Module", "square.grid.2x2", "Zeigt, welche Funktionen auf diesem Server und in deinem Konto eingeschaltet sind, dazu Serveradresse und Zeitzone. Umschalten geht in der Web-App.",
          web: "/settings/modules", keywords: "module funktionen ausblenden server adresse zeitzone"),
        e(.menuBar, .app, "Menüleiste", "menubar.rectangle", "Menüleistensymbol, Tastenkürzel und Hinweise bei laufendem Timer auf diesem Mac.", on: mac, keywords: "menüleiste dock tastenkürzel hinweise"),
        e(.activity, .app, "Aktivität", "square.stack.3d.up", "Lokales Protokoll der Vordergrund-App während eines Timers, nur für Notizvorschläge. Standardmäßig aus.", on: mac,
          keywords: "aktivität protokoll apps notiz vorschlag"),
        e(.appleWatch, .app, "Apple Watch", "applewatch", "Überträgt die aktuelle Anmeldung verschlüsselt an die Uhr.", on: phone, keywords: "watch uhr anmeldung übertragen"),
        e(.about, .app, "Über Timetrack", "info.circle", "Version, Lizenz und Support.", keywords: "über version lizenz support info")
    ]

    /// Visible entries grouped like the web app's `groupSettingsLinks`: group order from `SettingsGroupID`, empty groups disappear.
    public static func groups(platform: SettingsPlatform, isEnabled: (ModuleKey) -> Bool, query: String = "") -> [SettingsGroup] {
        let visible = all.filter { entry in
            entry.platforms.contains(platform) && (entry.module.map(isEnabled) ?? true) && matches(entry, query: query)
        }
        return SettingsGroupID.allCases.compactMap { id in
            let entries = visible.filter { $0.group == id }
            return entries.isEmpty ? nil : SettingsGroup(id: id, entries: entries)
        }
    }

    /// The web app's `searchSettings`: every word has to appear in the title or the keywords (case-insensitive).
    public static func matches(_ entry: SettingsEntry, query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        if words.isEmpty { return true }
        let haystack = "\(entry.title) \(entry.keywords)".lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}
