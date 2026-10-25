# X4: Review-Fixes (Codex-Befunde 1-7)

Branch `x4-review-fixes` (von main, Build 45). Nicht gemergt, nicht gepusht, kein Upload. Alle sieben Befunde wurden vor der Änderung im Code bestätigt.

| # | Schwere | Befund | Änderung |
|---|---|---|---|
| 1 | hoch | 404 beim Wiederöffnen galt als „Reopen nicht unterstützt“; war der Abschnitt inzwischen endgültig gelöscht, startete `resume` still einen neuen | 404 ist kein Ersatzstart-Signal mehr (`reopenUnsupportedStatuses` = 400/405/422/501). Eine verzögerte Fortführung mit 404 landet wie 409/412 in „Entscheidung nötig“ (`attention`), im direkten Aufruf wird der Fehler gezeigt |
| 2 | hoch | „Alle endgültig löschen“ zählte per Trockenlauf, löschte aber mit `all=true` | `CancelledStore.confirmationScope(for: .all)` liest die IDs zur Vorschau; Vorschau und Löschung gehen mit genau diesen IDs (Pakete von höchstens 500; 409 für inzwischen nicht mehr stornierte IDs bleibt gemeldet, Liste wird neu geladen). Die Bestätigungsansicht hält die bestätigte Menge |
| 3 | hoch | Kontowechsel: globale Warteschlange wurde nach dem Abmelden asynchron geleert, Konto B konnte Aktionen von A mit eigener Sitzung senden | `QueuedTimerAction.accountId`; `TimerActionQueue.bind(accountId:)` (Fence, wartet `AppModel.adopt`/`finishFastRestore` ab, bevor Stores liefern können) entfernt fremde Einträge, `release(accountId:)` (Vergleichen-und-Löschen) beim Abmelden, `drain(accountId:)` liefert nie fremde Einträge und löscht sie. Ohne Kontext (Erweiterungen) werden nur Einträge ohne Konto geliefert. Der Abmelde-Aufräumer in `TimetrackIOSApp` ist verkettet (`CleanupFence`), Arbeit des nächsten Kontos wartet darauf; `FocusEnvironment.signedOut` leert die Warteschlange nicht mehr; `TimerControlRunner` reiht ohne gespeicherte Sitzung nichts ein. Alteinträge ohne Konto übernimmt das erste gebundene Konto |
| 4 | mittel | Zwei parallele `load()` teilen `actionEpoch`; die ältere Antwort konnte die neuere überschreiben | `loadGeneration`; Ergebnis, Saldo und Fehler gelten nur für den neuesten Ladevorgang |
| 5 | mittel | Während `FormPDF.fill` blieben Eingaben änderbar, die ältere PDF wurde zurückgeschrieben | `inputGeneration` in `VacationRequestStore`: Ergebnis einer älteren Eingabe wird verworfen, auch `.saved` nach geänderter Eingabe; Eingaben in der Ansicht während der Erzeugung gesperrt |
| 6 | mittel | `prepareShare` lief nur bei geänderter Byte-Größe | `Generated.id` je Erzeugung; `.task(id: generated.id)`, Teilen-Datei in eigenem Ordner je Erzeugung |
| 7 | mittel | Konflikt-Einträge zählten bei der Obergrenze mit und konnten verdrängt werden | `trimmed`: nur lieferbare Einträge zählen gegen `limit`; `attention`-Einträge bleiben bis `discard`/`retry` |

## Tests (swift-testing, TimetrackCore)
- `ContinueLastTests`: 404 nie Ersatzstart (direkt und verzögert), Konflikt-Eintrag übersteht Verdrängung.
- `SuggestionsTrashTests`: genau die bestätigten IDs, Pakete zu 500, Konflikt im späteren Paket.
- `AccountQueueBindingTests` (neu): Stempel, bind/release, Alteinträge, drain fremd/ohne Kontext, TodayStore B liefert A nichts, Rennen Abmelden/Anmelden über `AppModel`.
- `RunningTimerRaceTests`: gehaltene Anfragen, älteres Ergebnis und älterer Fehler verlieren.
- `VacationFormTests`: veraltete PDF verworfen, neue ID je Erzeugung.

Kerntests 774 grün; Builds iOS, macOS, watchOS grün. Keine UI-Tests, kein Gerät; die Teilen-Datei (Befund 6) ist nur über die ID-Logik getestet, nicht in der Ansicht.

## Offen
- Alteinträge ohne Konto (vor X4 geschrieben) übernimmt das nächste Konto, das sich bindet; nur beim Update relevant.
- Erweiterungsprozesse kennen das Konto nicht und liefern nur Einträge ohne Konto.
