# P13-apple – Mehrere Planblöcke pro Tag (iOS, iPadOS, macOS)

Branch `p13-plan-blocks` (Worktree `timetrack-apple-wt/p13`, von `main` 84f0466, Build 51). **Nicht gemergt, nicht gepusht, nichts hochgeladen, Build-Nummer unverändert.** Vertrag 0.35.0, ADR-0031 (Backend), Referenz PWA: `P13-pwa.md`.

## Was gebaut ist

**Kern (`TimetrackCore`)**
- Modelle: `PlanBlockKind` (work, school, travel, office, home, customer, unknown), `PlanTimeBlock`, `PlanHint` (deutsche, unverbindliche Texte; unbekannte Hinweise werden verworfen), `PlanDay.blocks/planHints`, `PlanDayInput.blocks`, `TimeWeekDay.planBlocks/planHints/planActualDifferenceSeconds`, `SharedView.PlanDay.blocks` (nur Beginn, Ende, Art). Ältere Server ohne diese Felder dekodieren unverändert.
- `PlanBlocks.isSupported(apiVersion:)`: ab 0.35.0; unbekannte oder nicht lesbare Version zählt als alt.
- `DayDraft.blocks`; `WeekPlan.request(_, multi:)` sendet die vollständige, zeitlich geordnete Liste (`[]` bei „frei“ und Tagen ohne Uhrzeiten, keine Altfelder); `multi == false` sendet wie bisher ein Fenster mit Pause. Blockierte Tage senden ihren gespeicherten Plan samt Blöcken zurück. `WeekPlan.blocksProblem` prüft lokal Reihenfolge/Überschneidung, 32 Blöcke, Notizlänge 200, Uhrzeiten. `WeekPlan.hints(for:)` spiegelt die Server-Regel für Live-Hinweise. `WeekPlan.dayInput` für das Tagesblatt (alter Einzelwert bleibt erhalten, wenn kein Block ihn ausdrücken kann).
- `PlanBlockEditing`: hinzufügen, teilen, löschen, mit nächstem verbinden, sortieren, Lücken.
- `WeekPlanStore`: liest `apiVersion` einmal aus `/system/info` (Fehler = alter Modus, nächster Ladevorgang versucht es erneut), `supportsBlocks`, Block-Operationen, Dirty-Tracking über die Entwürfe, atomares Speichern der ganzen Woche. Moduswechsel füllt Blöcke aus dem Vorschlag (Pause als Lücke), färbt Blöcke der alten Tagesart um, „frei“ leert sie.
- Fehler: `plan_blocks_overlap`, `plan_blocks_invalid`, `plan_kind_invalid`, `plan_note_invalid` als `APIErrorCode` mit Katalogtext; `ErrorContext.planBlocks` liefert kontextbezogene deutsche Texte (auch für `plan_time_invalid`).
- `AppModel.planBlocksSupported`; `TodayStore.plannedBlocks`; `CalendarStore.savePlan` optimistisch mit Blöcken.
- **Kalender (EventKit/N2):** `CalendarEntry/WrittenEvent/CalendarLedgerRecord` haben optionale `startMinute/endMinute`. Ein Plantag mit Blöcken wird zu je einem Termin mit Uhrzeit pro Block, Schlüssel `plan/<Tag>/<n>` (n ab 1, zeitlich sortiert), Titel nach Art („Schule“, „Fahrt“, „Arbeit: Büro“ …), nie Ort/Notiz; Tage ohne Blöcke bleiben ein ganztägiger Termin `plan/<Tag>`. Reconciler-Semantik unverändert (Uhrzeitänderung = Update, überzähliger Block = Löschen, von Hand gelöschter unveränderter Block bleibt weg, Ledger alter Versionen dekodiert mit nil). Markerprüfung akzeptiert `plan/<Tag>/<n>`. Ganztägiger Alttermin eines Tages wird beim ersten Abgleich durch Blocktermine ersetzt.

**Oberfläche (`Sources/Week/PlanBlockViews.swift` u. a., iOS/iPadOS/macOS)**
- Wochenplaner: je Tag Blockeditor (Art-Menü mit Symbol, Farbe und Muster – Schule Streifen, Fahrt Punkte, Homeoffice Linien, Kunde Kreuzschraffur –; Beginn/Ende; Ort; Notiz; Menü Teilen/Mit nächstem verbinden/Löschen; „Block hinzufügen“), Tageszeitstrahl, Lückenanzeige, Live-Problemhinweis, Planungshinweise. Bei API < 0.35.0 bleibt die alte Einzelfenster-Oberfläche.
- Tagesblatt im Kalender (`PlanDaySheet`): gleicher Editor, schickt die Blockliste; Tagesdetail im Kalender zeigt Zeitstrahl und Blöcke einzeln.
- Zeit/Wochenansicht (`DayHeader`): Tage mit mehreren Blöcken zeigen Zeitstrahl und jeden Block einzeln, Chip „Ist gegenüber Plan ±h:mm“ (`planActualDifferenceSeconds`), Planungshinweise. Heute: Zeitstrahl und Zeile der Blöcke, wenn mehrere.
- Freigaben („Geteilt mit mir“): Blöcke mit Art und Zeit, ohne Ort/Notiz.
- Kalender-Einstellungen: Fußnote zu „Geplante Arbeitstage schreiben“ angepasst.
- Seed `scripts/seed-p13.py`, UI-Test `Tests/iOSUI/PlanBlocksTests.swift`.

## Prüfung
- Kerntests: `swift test --build-system native --no-parallel` 880 Tests grün (davon 23 neu in `PlanBlocksTests`: Dekodierung inkl. alter Server/Unbekanntes, Versionsprüfung, Entwurf, Fehlerabbildung, Store mit MockTransport, Rückfall, Kalenderschlüssel und -abgleich).
- Builds unsigniert: iOS (Simulator), macOS, watchOS grün. Die Uhr bleibt unverändert (kein Planer dort).
- UI-Test gegen Wegwerf-Backend (Debug-Binary aus Backend `main` mit P13): siehe Abschnitt „UI-Test“ unten.

## UI-Test
`Tests/iOSUI/PlanBlocksTests` (iPhone 18 Pro, Wegwerf-Backend aus Backend-`main` mit P13, Seed `scripts/seed-p13.py`, Port 18761): `testWeekListShowsEachBlock…` (Zeit-Wochenansicht zeigt Zeitstrahl und „08:00–12:00 Schule“) und `testSharedViewShowsBlocks…` (Freigabeansicht, Zeilen `share.plan.*`) **bestanden**. Der Wochenplaner (Block teilen/hinzufügen/löschen/speichern per Oberfläche) wurde im Simulator **gesichtet** (Bild `p13-planner`: Zeitstrahl Schule/Arbeit je Tag, Heute-Seite mit Blockzeile und Zeitstrahl), aber der automatisierte Bedienlauf scheiterte am Menüzugriff (XCUITest findet Einträge des Block-Menüs nicht) und wurde **entfernt**; das Speichern der vollständigen Liste ist durch die Kerntests (MockTransport) belegt, nicht per UI gegen das echte Backend.

## Nicht geprüft / offen
- Gerät, VoiceOver, große Schrift, iPad und das Mac-Fenster nicht gesichtet (Mac nur gebaut); EventKit-Schreiben mit echtem Kalender nur über den In-Memory-Provider getestet (zeitgebundene Termine, Lesen der Minuten aus `EKEvent`, Zeitzonenwechsel).
- Monatszellen des Kalenders zeigen weiter nur die Tagesart (Zellen zu klein); nur Sprachausgabe/Detail kennen Blöcke.
- Uhrzeiten werden über die Rad-Zeitwähler gesetzt, nicht per Ziehen auf dem Zeitstrahl (Zeitstrahl ist nur Anzeige).
- Block-Umordnung per Zeitwähler kann Reihenfolge verletzen: wird live benannt und beim Speichern nicht gesendet, nicht automatisch sortiert.
- Neue Texte stehen als deutsche Literale im Code (wie in `CalendarSettingsView`), nicht in den Katalogen.
- ICS-Abo ist Backend; Widgets/Live Activity nutzen unverändert das abgeleitete geplante Ende.
