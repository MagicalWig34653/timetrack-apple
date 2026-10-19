# Handoff N1b: Parität mit der PWA (Akzente, Leuchteffekt, Arbeitsmodell, Urlaubskarte, Haptik, Über Timetrack)

Branch `n1b-parity` (auf Basis von `main`, Build 8), 19.10.2026. Nicht gemergt, nicht gepusht, Build-Nummer unverändert, kein TestFlight-Upload.
Grundlage: Backend Vertrag 0.23.0, ADR-0020 (Nachtrag AC2), ADR-0023, ADR-0004-Nachtrag (M1), Handoffs AC2 und M1; PWA `theme/accent.ts`, `glow.ts`, `work-model`, `VacationBalanceCard`, `VersionInfo`.

## Was gebaut wurde

1. **Akzente (22 IDs).** `AccentPreset` (Core) kennt alle IDs des Vertrags in Anzeigereihenfolge der PWA, `custom` zuletzt; `nativeHex` je Voreinstellung (die sieben alten behalten die nativen Farbtöne, die 14 neuen die PWA-Werte aus AC2/accent.ts). `AccentChoice` im Design-Paket ist jetzt ein Alias darauf. Weiße Schrift auf der Fläche: alle 14 neuen Töne haben >= 4,5:1 mit Weiß (Test). Deutsche Namen wie in der PWA (Indigo, Marine, Purpur, Magenta, Karmin, Waldgrün, Petrol, Bronze, Wein, Schiefer, Kakao, Oliv, Ozean, Tinte) in den Katalogen iOS und Mac. Unbekannte ID: Blau. Das Raster ist ein adaptives `LazyVGrid` (Mindestbreite 72 pt).
2. **Server vor v0.21.0 / v0.15.0.** Lehnt der Server eine ID oder `glow` mit 400 ab, sendet `AppearanceSync` Ersatz-Patches (`LocalAppearance.fallbackPatches`): neue ID als `custom` plus Hex (wie die PWA), zuletzt ohne `glow`. Der Leuchteffekt bleibt dann lokal.
3. **Leuchteffekt.** `GlowPreference` (off/subtle/medium/strong, Standard subtle), Schlüssel `appearance.glow`, Teil von `LocalAppearance` und `PreferencesPatch`; fehlt `glow` in der Serverantwort (alter Server), bleibt der lokale Wert. Darstellungsseite: Segmentwahl mit Beschreibung. Wirkung (`GlowStyle`, rein, getestet): Hof unter Hauptknöpfen (`ttHalo`), Hof um Ringe (`ttRingHalo`), farbige Kartenkanten ab Mittel, stärkere weiche Akzentlichter im Hintergrund (Faktor 0/1/1,5/2,2). **Transparenz reduzieren oder Kontrast erhöhen schaltet alle Höfe, Kanten und die Hintergrundverstärkung ab** (Stufe bleibt gespeichert). Nicht umgesetzt: Glasfläche des Hauptbereichs auf „Stark“ (PWA), weil Glas hier nur Rahmen/Hero ist (DESIGN-NATIVE Regel 1).
4. **Arbeitsmodell bearbeiten.** Einstellungen › Arbeitsmodell (iOS Navigation, Mac Blatt aus dem Einstellungsfenster): Liste aller Versionen (aktuell/geplant), „Version korrigieren“ öffnet ein Blatt mit auffälligem roten Warnfeld, Formular (Zeitraum, Wochen-Soll, Arbeitstage, Zeitzone, Tagesgrenze, Rundung, Fahrtzeit, Schulschwelle/-gutschrift, feste Pausen; Tages-Soll je Wochentag bleibt unverändert erhalten, entfernbar), Live-Vorschau (`POST /work-models/{id}/preview`, 350 ms entprellt) und Bestätigungsschalter. Speichern (`PUT`, `If-Match: version`) erst nach Vorschau **desselben** Eingabestands und Bestätigung; jede Änderung setzt die Bestätigung zurück. 409 `model_overlap` und 412 `stale_version` haben eigene Texte. Server ohne `version`: nur Anzeige mit Hinweis. Nicht umgesetzt: „Ab einem Datum ändern“ (neue Version per POST) und „Version beenden“ (PATCH).
5. **Urlaubskarte.** `VacationFigures` auf dem Urlaub-Tab: Kacheln Anspruch, Übertrag, Korrekturen, (Stichtagsbestand), Genehmigt/genommen, Geplant (bei Stichtagsbestand zeigen Anspruch/Übertrag die gespeicherten Werte als „ersetzt“, wie die PWA) und „Anspruch ändern“ (Blatt nur für den Jahresanspruch, `PUT /vacation/settings` mit unveränderten übrigen Feldern). Verfügbar/Nach Planung stehen weiter im Ring darüber.
6. **Haptik.** `HapticsToggle` (Design-Paket): Aus-/Ein-Schalter auf iOS (Einstellungen, zusätzlich zur Dezent/Normal-Wahl in Darstellung), Mac (Allgemein) und Watch (Einstellungen). Ein behält eine gewählte Stufe „Dezent“, sonst „Normal“.
7. **Über Timetrack.** `AboutSection` (iOS, Mac): App-Version (Build), Lizenz, Server-Version, Revision (7 Zeichen), Bauzeit, API-Version; für Administratoren zusätzlich Datenbank, Migrationen (ggf. „weitere ausstehend“), Laufzeit, Replikat. Ältere Server ohne Endpunkt (404 oder Fehler): Hinweistext, nur App-Version. „Angaben für den Support kopieren“ kopiert eine Zeile wie in der PWA (`Timetrack iOS 0.1.0 (8), Backend 0.1.0 (abc1234, 2026-10-18), API 0.23.0, mariadb`). `AppModel.refreshSystemInfo()` lädt bei jedem Öffnen. Die Watch hat weiter nur Version/Lizenz.

## Dateien

Core: `Models/Preferences.swift`, `Models/SystemInfo.swift`, `Models/WorkModel.swift` (Eingabe, Vorschau, Formular), `Preferences/AppearanceSync.swift`, `Networking/APIClient.swift`, `TimetrackStores/WorkModelStore.swift`, `AppModel.swift` (`systemInfo`, `reloadWorkModel`). Design: `Glow.swift`, `HapticsToggle.swift`, `AppearancePreferences.swift`, `AppearanceSettings.swift`, `Controls.swift`, `DataViews.swift`, `Surfaces.swift`. Apps: neues Verzeichnis `Sources/Settings` (iOS und Mac), `Sources/{iOS,Mac,Watch}/SettingsView.swift|SettingsScreen.swift`, `Sources/Planning/VacationScreen.swift` (eine Zeile), Kataloge. Tests: `Tests/iOSUI/ParityFlowTests.swift`.

## Geteilte Dateien (Merge)

`project.yml` (je eine Zeile `Sources/Settings` bei iOS und Mac; `Timetrack.xcodeproj` mit `xcodegen generate` neu erzeugen, nie von Hand auflösen), `AppModel.swift`, `VacationScreen.swift`, Kataloge (nur Einträge hinzugefügt).

## Prüfung

Zahlen und Befunde: siehe `docs/STATUS.md` Zeile N1b. UI-Durchlauf `ParityFlowTests` gegen Wegwerf-Backend (Backend-Binary mit Vertrag 0.23.0): Urlaub-Kacheln, Anspruch ändern, Arbeitsmodell korrigieren mit Vorschau und Bestätigung, Über Timetrack (Administrator), Akzent „Tinte“, Leuchteffekt „Stark“.

## Offen

- Gerät: Gefühl der Höfe auf echten Displays, Kontrast-erhöhen-Darstellung, Dynamic Type im Arbeitsmodell-Blatt, Mac-Oberfläche nur gebaut.
- Mitglied-Ansicht von „Über Timetrack“ nur per Unit-Test (Fixture), nicht im UI (Wegwerf-Konto ist Administrator).
- Watch: Akzent weiter Standardblau (nur Komplikation folgt dem Konto).
- Native Töne von Türkis/Orange/Rosa weichen weiter von der PWA ab (bewusst, DESIGN-NATIVE).
