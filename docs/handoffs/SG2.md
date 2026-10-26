# SG2 – Storniert: Mehrfachauswahl nutzbar (Build-46-Fehlermeldung)

Branch `sg2-cancelled-bulk` (Worktree `timetrack-apple-wt/sg2`) von `main` (Build 46). Nicht gemergt, nicht gepusht, nichts hochgeladen, Build-Nummer unverändert.

## Befund
Meldung: „Wenn man mehrere stornierte Einträge auswählt, kann man damit nichts machen.“ Ursachen: (1) „Alle auswählen“ und „Endgültig löschen“ lagen in einer `.bottomBar`-Toolbar des gepushten Bildschirms, die hinter Jetzt-Leiste/Tab-Leiste verschwand; (2) es gab keine Sammelaktion „Wiederherstellen“.

## Änderung
- **Kern:** `CancelledStore.restore(_ items:)` stellt mehrere Einträge einzeln mit eigenem If-Match wieder her, sammelt je Eintrag das Ergebnis (`BulkRestoreResult`: `restored`, `failed` mit `RestoreFailure`, `failedIds`) und lädt die Liste einmal am Ende neu. Ein Konflikt (409 `segment_overlap`/`timer_already_running`, geändert) bricht den Rest nicht ab.
- **UI (`CancelledViews.swift`, iPhone/iPad/Mac):** Toolbar-Gruppe entfernt; stattdessen `safeAreaInset(edge: .bottom)`-Leiste über Jetzt-Leiste und Tab-Leiste: „n ausgewählt“, „Alle auswählen“/„Keine auswählen“, „Wiederherstellen (n)“ (primär), „Endgültig löschen (n)“ (bestehender Ablauf: Trockenlauf-Zählung, Wort tippen, bestätigte Ids). Zeilentipp wählt aus, Karten-Aktionen für Einzeleinträge unverändert, „Fertig“ beendet den Modus.
- **Teilerfolg:** Blatt „Wiederherstellen“ mit Anzahl wiederhergestellt/nicht wiederhergestellt und je abgelehntem Eintrag Tag/Uhrzeit und Grund; abgelehnte bleiben ausgewählt, Hinweiszeile „Wiederhergestellt: n“. Vollerfolg beendet den Auswahlmodus. Heute/Zeit/Zu prüfen laden neu.
- Accessibility-IDs `cancelled.*` bleiben; neu `cancelled.restore_selected`, `cancelled.selected_count`, `cancelled.report(.line/.close)`; `cancelled.select_all` und `cancelled.purge_selected` jetzt in der Leiste. Strings `sg2.*` in `SG1.xcstrings`.

## Prüfung
- Kerntests 776; neu `bulkRestoreReportsPartialFailuresPerEntry`, `bulkRestoreOfEverythingIsComplete`; grün bis auf `weekStoreLoadsAndShifts` (WeekVacationTests, Datumsannahme „aktuelle Woche = 2026-W43“, unabhängig von SG2).
- Builds unsigniert iOS, macOS, watchOS: BUILD SUCCEEDED.
- UI-Test `SuggestionsTrashTests.testCancelledBulkSelectionRestoreAndPurge` (iPhone 18 Pro, Wegwerf-Backend aus `main`, Seed `seed-sg1.py`): zwei Einträge wählen (einer überschneidet), Leiste erreichbar, Wiederherstellen (2) bringt einen zurück, einer wird abgelehnt (Blatt, bleibt ausgewählt), dann Alle auswählen und Endgültig löschen mit Wort leert den Papierkorb. Bestanden. Bilder `docs/screenshots/sg2-bulk-*` gesichtet: Leiste liegt sichtbar über Jetzt-/Tab-Leiste. Danach wurde nur eine unbenutzte Variable aus dem Test entfernt (nicht erneut gelaufen).

## Offen
iPad und Mac-Fenster nicht gesehen (Mac nur gebaut), VoiceOver/große Schrift ungeprüft.
