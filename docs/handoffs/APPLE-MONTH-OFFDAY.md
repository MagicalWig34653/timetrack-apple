# APPLE-MONTH-OFFDAY

Stand: 03.11.2026. Branch `apple-month-offday`, Ausgangscommit `bfdc706` (TestFlight Build 60).
Isolierter Clone `tt-apple-pkg` im temporären Verzeichnis; Hauptcheckout und Backend unverändert.
Nicht integriert, kein Push, kein TestFlight-Upload. Keine Abhängigkeiten, Migrationen oder neuen App-Schalter.

## Monatsfehler

`CalendarScreen.swift` ist im aktuellen Stand nur der Mac-Bildschirm. Die iOS-/iPadOS-Monatsansicht
liegt in `Sources/Week/MonthPager.swift` (`MonthList`). Deren `LazyVStack` enthält Monatsabschnitte
mit `ForEach(snapshot.monthRows, id: \.cells[0].day)`. Randwochen erscheinen in beiden angrenzenden
Monaten: etwa die Woche ab 26.10.2026 im Oktober und November. Damit hatten die beiden Zeilen
dieselbe explizite Identität im fortlaufenden Lazy-Container. Der Zeileninhalt unterscheidet sich
(`inMonth` blendet jeweils andere Tage aus). Das ist ein konkreter Identitätsfehler und erklärt
fehlende/falsch wiederverwendete Wochen. Der konkrete TestFlight-Bildschirm wurde hier nicht reproduziert.

`MonthKey.gridDays` erzeugt dagegen vollständig 42 eindeutige Tage in UTC, Montag zuerst;
`monthRows` reduziert auf 4–6 berührte Wochen. `CalendarStore.gridDays` erzeugt die passenden
4–6 Wochen für den Mac. Kein nachgewiesener Fehler in `firstWeekday`, ISO-Wochennummern oder DST.
Diese Berechnungen und die Höhenberechnung bleiben unverändert.

Änderung: `MonthWeekSnapshot` ersetzt das bisherige Tupel. Seine ID enthält Monatsindex und
Wochenbeginn, ist über Datenänderungen hinweg stabil und unterscheidet gemeinsame Randwochen.
Die iOS-Liste verwendet dieses `Identifiable` direkt. Keine Änderung der Tages-IDs oder Mac-Ansicht.

Dateien:

- `Packages/TimetrackCore/Sources/TimetrackStores/Calendar/MonthSnapshot.swift`
- `Sources/Week/MonthPager.swift`
- `Packages/TimetrackCore/Tests/TimetrackCoreTests/MonthRowRegressionTests.swift`
- `Packages/TimetrackCore/Tests/TimetrackCoreTests/PlanBlocksTests.swift`
- `docs/STATUS.md`, diese Übergabe

## PLAN-OFFDAY und VB1

Die Umsetzung war bereits im Ausgangscommit vorhanden:

- `PlanWeekDay.blockedBy` bleibt API-Information, `isOffDay` dient der Anzeige; kein `isBlocked` mehr.
- `WeekPlanStore.editable`, Zeichnen, Verschieben, Größenänderung, Kopieren und Tagesart sperren
  Markertage nicht. Raster und Tageskopf zeigen Marker, keine Sperrfläche.
- Plansummen zählen diese Tage. Sammelaktionen behalten bewusst ihre bestehende Semantik
  (Standardwoche/Gleiche Woche/Vorwoche lassen Markertage unverändert, Woche leeren leert sie).
- Deutscher Planhinweis: „Plan an einem Urlaubstag zählt als geplante Mehrzeit.“
- VB1: `VacationBooking` und `VacationBookingNote` zeigen bereits den Hinweis
  „Buchung an Urlaubstag: Die gebuchte Zeit zählt als Überstunde.“
  Buchungen und Ist-Anzeige waren bereits freigegeben.
- Plan/Ist wird im aktuellen Client nicht als eigene Ansicht verwendet; keine neue Ansicht ergänzt.

Der bisherige Storetest nur für Urlaub ist nun für `vacation`, `sick`, `excused`, `holiday`
parametrisiert (Zeichnen, Kopieren, Plansumme, Hinweis nur bei Urlaub). Vorhandene Tests prüfen
Speichern, Verschieben, Undo/Redo und VB1. Keine Gutschriftlogik, Zeitkonto- oder Urlaubsbewertung geändert.
Die offene Produktfrage zur ausdrücklichen Gutschrift an Urlaubstagen bleibt offen und blockiert
keine der Änderungen dieses Pakets. Maßgeblich: Backend-Handoffs PLAN-OFFDAY, VACATION-BOOKINGS und ADR-0035.

## Tatsächliche Prüfungen und Grenzen

Alle temporären Dateien, Logs, Home-/Cache-Umleitungen und DerivedData liegen im selben Clone
unter `.task-tmp`, `.task-cache`, `.task-home`, `DerivedData` beziehungsweise paketlokal `.build`.
Temporäre Verzeichnisse sind lokal ausgeschlossen und werden nicht committet.

1. Vor der ID-Korrektur: `swift test --build-system native --filter MonthRowRegressionTests`
   in `Packages/TimetrackCore`, nach verhaltensgleicher Extraktion der bisherigen ID in den Zeilentyp.
   Exit 1 bei Manifestausführung: `sandbox-exec: sandbox_apply: Operation not permitted`.
   Keine Assertion ausgeführt. Log `.task-tmp/before.log`.
2. Nach der Korrektur: `swift test --build-system native` jeweils in `Packages/TimetrackCore`
   und `Packages/TimetrackDesign`. Beide Exit 1 mit derselben Sandbox-Ursache vor Testausführung.
   Logs `.task-tmp/core.log`, `.task-tmp/design.log`. Kein Rot/Grün-Nachweis möglich.
3. `swiftc -frontend -parse` für die vier geänderten Swift-Dateien: Exit 0.
   Das ist nur Syntaxprüfung, kein Typcheck oder Ersatz für Unit-Tests.
4. `git diff --check`: Exit 0.
5. `xcodebuild -project Timetrack.xcodeproj -scheme TimetrackIOS -showdestinations
   -derivedDataPath <clone>/DerivedData`: Exit 74; Paketauflösung scheitert (`ManifestLoading`),
   zusätzlich CoreSimulatorService nicht erreichbar. Daher keine Xcode-Tests und kein App-Build.
   Log `.task-tmp/destinations.log`. Kein Simulator-/Gerätetest.

Die neue Identitätsregression würde mit der alten ID-Definition doppelte IDs erkennen; dies ist
statisch nachvollziehbar, aber hier ausdrücklich kein gemessener fehlgeschlagener Testlauf.
Die übrigen Tests prüfen jede Tagesfolge, Wochenbeginn/-nummer, sichtbare Monatstage und Layout-
Höhen für Montag-/Sonntagstarts, 4/5/6 Wochen, ISO-Woche 53, DST-Monate in Berlin/New York sowie
stabile IDs bei erneutem Snapshot und geänderten Markern.

## Abweichungen vom Auftrag

- PLAN-OFFDAY/VB1 brauchten keine erneute Produktänderung, da schon implementiert; Tests erweitert.
- Verlangter Unit-Test-Rot/Grün-Nachweis ist durch die Laufzeitumgebung blockiert.
- Backend-Status/Arbeitsplan bleiben gemäß Auftrag schreibgeschützt; Ergebnis lokal dokumentiert.

## Nächster Schritt / Rückfragen

Die vollständigen Paketsuites und die Identitätsregression müssen in einer Umgebung laufen,
in der SwiftPM seine Sandbox starten kann. Für den Rot-Nachweis bei unverändertem neuen Test
nur `MonthWeekSnapshot.id` vorübergehend auf `cells[0].day` setzen; danach wiederherstellen.
Alternativ ist zu klären, ob die Testoption `--disable-sandbox` trotz „keine neuen Flags“ erlaubt ist.
Danach auf Simulator/Gerät Oktober–November und Dezember–Januar durchscrollen, zurückspringen,
Daten neu laden sowie Auswahl und große Schrift prüfen. Offday-Gesten auf allen vier Markertagen
prüfen. Keine laufenden Jobs oder Dienste; keine Daten-/Migrationsfolgen.
