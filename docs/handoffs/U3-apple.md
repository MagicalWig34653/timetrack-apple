# U3-apple – Fehler (Timer durch Ort, 409), Jetzt-Sync, Orte archivieren, Urlaubskonto, Mehr/Einstellungen

Branch `u3-bugs-vacation` (von `main`). Nicht gemergt, nicht gepusht, nichts hochgeladen, Build-Nummer unverändert.

## 1. Timer durch Ort / 409 `timer_already_running`
- Befund: `TodayStore.load` lief nur beim Erscheinen von Heute und beim Vordergrund dieser Ansicht; auf anderen Tabs, bei Mitteilungen und während die App offen war, wurde ein serverseitig (Ortsautomatik, Link, Watch, Web) gestarteter Timer nicht gesehen. Ein manueller Start lief dann in 409 und zeigte den Fehler.
- Kern: `TodayStore.refreshRunning()` (eine Anfrage, voller Reload nur bei Änderung; überspringt bei laufendem Load, eigener Aktion oder wartender Warteschlange), `conflict`/`TimerConflict`, `switchRunning(to:)`. 409 beim Start (mit und ohne Warteschlange, auch Fortführen) lädt den Zustand neu und zeigt den laufenden Timer ohne Fehler; bei anderer Art erscheint „Läuft bereits … / Zu X wechseln / Weiterlaufen lassen“. Bleibt nach dem Reload kein Timer, bleibt der Fehler.
- App (`Sources/Common/U3Support.swift`): `timerFreshness` auf iOS-`MainView` und Mac-`RootView`: beim Aktivwerden, alle 30 s solange aktiv, bei `.ttTimerChangedExternally` (neu auch nach Automatik-Weckrufen/Prüfungen und bei jeder Mitteilung im Vordergrund). Stiller Push lädt weiterhin (P14c).

## 2. Kalender „Jetzt synchronisieren“
`DeviceCalendarStore.syncNow`, `isSyncing`, `lastSyncReport` (`synced(created,updated,deleted)`, `nothingToWrite`, `serverUnreachable`, `writeFailed`), `lastSyncAt`. Neuer Abschnitt „Synchronisation“ in den Kalender-Einstellungen (Knopf mit Fortschritt, zuletzt, Ergebnis).

## 3. Orte archivieren
Vertrag: `DELETE /places/{id}` archiviert; Liste enthält keine archivierten Orte, kein Wiederherstellen und kein „Archivierte anzeigen“ möglich (nicht im Vertrag; Filter bewusst nicht gebaut, Backend-Wunsch). `APIClient.archivePlace`, `AutomationStore.archive` (404 = erledigt; Engine verwirft Region/Zustand). iOS: Button je Ort mit Rückfrage und VoiceOver-Label/Hinweis; Mac: Kontextmenü/Accessibility-Aktion mit Rückfrage. Archivierte Orte werden von der Automatik ignoriert (Test).

## 4. Urlaubskonto
Neue `VacationAccountCard`: große Resttage, segmentierter Balken (Genommen/Genehmigt/Beantragt/Geplant/Frei) mit Legende, Jahresanspruch, Übertrag, Korrekturen, Verfallshinweis; darunter unverändert die Blöcke mit Status-Chips. Zeile „Erinnerungen“ vom Urlaub-Tab entfernt (bleibt unter Einstellungen). Aufteilung Genommen/Genehmigt und Beantragt/Geplant aus den Abwesenheiten des Jahres (Balance liefert nur Summen); alter Ring bleibt im Code (`VacationRing`), wird nicht mehr genutzt.

## 5. Mehr vs. Einstellungen
Mehr = Funktionen (Zu prüfen, Storniert, Statistik, Berichtsheft, Orte und Automatik, Im Web, Zeile Einstellungen), ohne Kontokarte. Einstellungen = Konto, Darstellung, Arbeit, Erinnerungen, Automatik und Kalender, Watch, Info, Abmelden. UI-Tests angepasst (NowBarTests, PushFeedsTests, AutomationFlowTests), `glossary-ui.md` ergänzt. iPad-Seitenleiste unverändert (Mehr bleibt Eintrag, Inhalt neu); Mac hat keine Mehr-Seite.

## Prüfung
- Core: `swift test --build-system native --no-parallel`: 909 Tests grün (neu: 6 `TimerConflictTests`, 3 Kalender-Sync, 4 Orte).
- Unsignierte Builds iOS (Simulator), macOS, watchOS: BUILD SUCCEEDED.

## Nicht geprüft
UI-Tests nicht ausgeführt (angepasst, kein neuer UI-Test für 409 – der Pfad ist per Core-Tests belegt); keine Screenshots; Optik von Urlaubskonto/Toast/Sync-Abschnitt nicht im Simulator gesehen; echte Ortsauslösung und Polling-Takt (30 s) auf dem Gerät; Mac-Archivieren nur gebaut.
