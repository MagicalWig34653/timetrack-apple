# Handoff SET-A: Einstellungen an die PWA angeglichen (iOS, iPadOS, macOS)

Branch `set-a` (von main), nicht gepusht, Build-Nummer unverändert, kein Upload.

## Struktur
Neue testbare Kernstruktur `Packages/TimetrackCore/Sources/TimetrackCore/Support/SettingsStructure.swift` (Spiegel von `nav.ts` der PWA):
acht Gruppen-IDs mit den Namen der PWA (Profil & Sicherheit, Arbeitszeit & Urlaub, Orte & Automatik, Benachrichtigungen & Kalender, KI-Zugang, Daten & Export, Darstellung & Module, Verwaltung (Admin)), Einträge mit Titel, Beschreibung (Texte der PWA), Modul, Plattformen, Suchwörtern. Leere Gruppen verschwinden: KI-Zugang und Verwaltung erscheinen nativ nie (gibt es nativ nicht, kein Platzhalter).

Native Einträge je Gruppe (Reihenfolge wie PWA):
- Profil & Sicherheit: Profil, Passkeys, Verknüpfte Anmeldungen, Wiederherstellung, Sitzungen (der Hub „Konto und Sicherheit“ entfällt, die Seiten sind unverändert).
- Arbeitszeit & Urlaub: Arbeitsmodell, Zeitkonto, Urlaubsanspruch (nur iOS, nativ-eigen), Lernfelder (Modul Berichtsheft, neuer Einstieg `LearningFieldsScreen`), Freigaben (Modul Planung).
- Orte & Automatik: Orte, Auslöse-Links, Fokus-Filter (nur iOS, nativ-eigen); alle mit Modul Automatik.
- Benachrichtigungen & Kalender: Hinweise & Push, Urlaubserinnerungen und Überstunden-Hinweise (nur iOS, nativ-eigen), Kalender-Abos, Kalender (Gerätekalender, nativ-eigen).
- Daten & Export: Export (iOS, öffnet die Web-App), Stornierte Einträge (iOS).
- Darstellung & Module: Darstellung, Module (nativ nur lesend), Menüleiste und Aktivität (nur Mac), Apple Watch (nur iOS), Über Timetrack.

## Gestaltung
`Sources/Settings/SettingsLanding.swift`: Gruppenüberschrift fett mit Linie darunter; Einträge als Zeilen einer Listenkarte mit Titel, Beschreibung (max. zwei Zeilen) und Pfeil. Keine einseitigen Rahmen, keine Akzentbalken. iOS: `SettingsView` mit Suche (`.searchable`, Titel und Suchwörter wie PWA). macOS: Einstellungsfenster als `NavigationSplitView` (Seitenleiste mit Gruppen, Detail: Übersicht oder Seite) statt Tab-Leiste; Abmelden und Server wechseln auf der Übersicht, Haptik-Schalter jetzt unter Darstellung.

## Abweichungen und offene Punkte
- Beschreibungen nativ-eigener Einträge sowie „Module“ (nativ nur lesend) und „Darstellung“ (ohne den Browser-Satz) sind von mir formuliert, nicht aus der PWA.
- Fehlt nativ (weggelassen): Urlaubsantrag-Vorlage, Geräte, Import, Daten & Datenschutz, KI-Zugang (Verbindungen, API-Tokens, KI-Anbindung), Verwaltung (Admin), Dateispeicher.
- „Orte“ ist an das Modul Automatik gebunden (wie bisher in „Mehr“); in der PWA ist die Seite Kern. Auf dem Mac sind Orte vorher ungegatet gewesen.
- Mac: Urlaubsanspruch, Urlaubserinnerungen, Überstunden-Hinweise, Fokus-Filter, Export, Stornierte Einträge nicht in den Einstellungen (dort wie vorher nicht vorhanden bzw. in der Seitenleiste der App).
- Accessibility-Kennungen der Zeilen bleiben, soweit vorher vorhanden (`settings.workmodel` usw.). Die UI-Tests wurden nicht ausgeführt; bei Tests, die „Konto und Sicherheit“ über den Hub ansteuern, wäre der Pfad anzupassen (keine im Repo gefunden).
- Mac-Fenster und iOS-Layout nicht auf Gerät/Simulator gesichtet (nur Build).

## Prüfung
Kerntests 1006 grün (`swift test --build-system native`, davon 6 neu in `SettingsStructureTests`). Builds grün: TimetrackIOS (generic/platform=iOS Simulator) und TimetrackMac (platform=macOS), gebaut aus einer Kopie unter /private/tmp (im iCloud-Ordner hängt xcodebuild beim Laden des Projekts). UI-Tests nicht ausgeführt.
