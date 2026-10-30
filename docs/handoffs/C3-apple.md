# C3-apple – Abwesenheitsstatus je Art, Zeitkonto ohne heutigen Tag, Konto-Mail als Recovery

Stand: 29.10.2026, Branch `c3a-absence-clients` (Basis main), nicht gemergt. Gegenstück: Backend `docs/handoffs/C3-backend.md`, ADR-0032, Vertrag 0.36.0.

## Geändert
1. **Status tolerant** (`Models/Planning.swift`): `AbsenceStatus.recorded` ("erfasst"); unbekannte oder fehlende Werte werden `.unknown` (auch bei `Absence`, `TimeWeekAbsence`). Hilfsfunktionen `valid(for:)`, `isValid(for:)`, `serverDefault(for:)`, `sendable(for:)` (Altwerte approved/taken/requested werden für Nicht-Urlaub zu `recorded`, Ungültiges entfällt), `isApprovalFlow`. `AbsenceInput.status` ist optional und wird nur gesendet, wenn gesetzt und bekannt. Kalender-Titel: Krank + `recorded` = "Krank"; Filter-/Sortierliste kennt `recorded`.
2. **Abwesenheitseditor**: Statuswahl nur bei Urlaub; Krank/Freistellung/Sonstiges zeigen "Wird als „erfasst“ gespeichert." und senden nie einen Genehmigungsstatus (bei Bearbeitung bleibt ein gültiger Status wie `cancelled` erhalten, sonst wird `status` weggelassen). Labels "erfasst/Erfasst". Urlaubskonto zählt weiter nur Urlaub (Aufschlüsselung filtert nach Art).
3. **Zeitkonto ohne heute**: `TimeAccount`, `TimeWeekSummary`, `TimeStatistics` mit `includesToday` und `todayDeltaSeconds` (optional, ältere Server unverändert). Anzeige "Heute: +0:42, fließt morgen ein" im Zeitkonto-Bildschirm, in der Wochenzusammenfassung (Bildunterschrift "bis gestern"), unter den Statistik-Kacheln und als Bildunterschrift der Heute-Saldo-Kachel.
4. **Wiederherstellungs-Mail**: Die App hat keine Oberfläche und kein Modell für `/me/recovery` (Einrichtung/Profil liegen in der PWA); nichts umgesetzt, kein Adressfeld zu entfernen.

## Tests
`Tests/TimetrackCoreTests/AbsenceSemanticsTests.swift` (11 Tests: Dekodierung recorded/unbekannt/fehlend in Liste und Woche, Gültigkeitsmatrix, `sendable`, Input-Kodierung, Kalendertitel, Kontofelder, Statistik, Wochen-Summary). Gesamt 920 Kerntests grün (`swift test --build-system native --no-parallel`).

## Nicht geprüft
Kein Lauf gegen ein echtes Backend 0.36.0; UI nicht im Simulator gesichtet (Editor ohne Statuswahl, Heute-Zeilen). Watch/Widgets zeigen weiter `balanceSeconds` ohne Heute-Zeile. Lokalisierung der neuen Texte nur Deutsch.
