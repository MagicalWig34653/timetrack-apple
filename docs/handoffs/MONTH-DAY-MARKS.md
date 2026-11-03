# MONTH-DAY-MARKS

Stand: 03.11.2026. Branch `month-day-marks`, Ausgangscommit `fd983b6` (Build 61).
Codex ist alleiniger Schreiber im frischen temporären Clone `tt-apple-mark`.
Hauptcheckout und Backend unverändert; kein Push, kein TestFlight.

## Ursache und Änderung

Die vermutete Ursache ist im Code bestätigt: `MonthSnapshot.build` bekam die
Tagesauswertungen bereits übergeben, verwendete sie aber nur für `workedSeconds`.
Pillen und Marker wurden ausschließlich aus Abwesenheiten, Feiertagen und Plan gebaut.

`MonthPill.pills(for:mark:)` ergänzt für `vacation`, `sick` und `excused` eine
gefüllte Pille mit `.absence(kind)` und ohne eigenen Text. Eine gemeinsame lokale
Zuordnung prüft, ob bereits eine Abwesenheit derselben Art den Tag abdeckt; dann
bleibt deren Pille einschließlich des bisherigen Status unverändert und es entsteht
kein zusätzlicher Eintrag. Abwesenheiten anderer Arten unterdrücken die Tagesmarkierung nicht.
Die Marker verwenden dieselbe Zuordnung und Duplikatprüfung.

Bestehende Abwesenheiten behalten ihre Reihenfolge, zusätzliche Tagesmarkierungen
stehen im Abwesenheitsblock vor Feiertag und Plan. Die Grenzen von zwei
Abwesenheitsmarkern und drei Gesamtmarkern sowie `MonthPill.visible` bleiben erhalten.
`holiday`, `unmarked` (`none`), `schoolCredit`, `unknown` und nil ergänzen nichts;
Feiertage kommen weiterhin aus den Kalenderdaten. Keine synthetischen Abwesenheitsrecords,
keine Änderung an Bewertung, Speichern, API, UI-Texten oder anderen Ansichten.
Keine neuen Abhängigkeiten, Flags, Migrationen oder Datenfolgen.

## Dateien und Abnahme

- `Packages/TimetrackCore/Sources/TimetrackStores/Calendar/MonthSnapshot.swift`
- `Packages/TimetrackCore/Tests/TimetrackCoreTests/TimeCalendarWindowTests.swift`
- `docs/STATUS.md`
- `docs/handoffs/MONTH-DAY-MARKS.md`

Vier neue Testfunktionen mit insgesamt 12 Fällen: alle drei darstellbaren
Tagesmarkierungen ohne Abwesenheit, alle drei mit passender Abwesenheit (eine Pille,
bestehender Umrissstatus bleibt erhalten), fünf nicht darstellbare Markierungswerte
jeweils mit/ohne Kalenderfeiertag sowie Kombination mit anderer Abwesenheit,
Feiertag, Plan und Überlauf. Vorhandene Prioritäts-/Kapazitätstests bleiben bestehen.

## Tatsächliche Prüfungen

`swift test --build-system native` in `Packages/TimetrackCore`: Exit 1.
0 Tests ausgeführt; 0 bestanden, 0 fehlgeschlagene Testfälle gemessen.
Der Build scheitert bereits bei der Manifestausführung (zweimal dieselbe Ursache):

```text
sandbox-exec: sandbox_apply: Operation not permitted
```

SwiftPM meldet dazu `Invalid manifest` und die Deprecation-Warnung für
`--build-system native`; kein Compiler- oder Assertionsergebnis für den geänderten Code.
Vollständiges lokales Log: `.task-tmp/core-tests.log` (nicht committet).
Home, Caches und temporäre Dateien sind per Umgebungsvariablen in `.task-home`,
`.task-cache` und `.task-tmp` innerhalb des Clones umgeleitet; Buildprodukte paketlokal
in `.build`. Diese Arbeitsdateien sind lokal ausgeschlossen und bleiben erhalten.
Keine zusätzlichen Testflags oder Sandbox-Umgehung verwendet.
`git diff --check`: Exit 0. Kein App-Build, Simulator- oder Gerätetest ausgeführt.

## Übergabe und nächster Schritt

Implementierung abgeschlossen, Testnachweis offen: den unveränderten vorgegebenen
Core-Testbefehl in einer Umgebung mit funktionierender SwiftPM-Sandbox ausführen,
danach Tagesmarkierungen in der iOS-Monatsliste prüfen und Commit integrieren.
Keine laufenden Jobs/Dienste. Clone bleibt zur Übernahme erhalten.

## Abweichungen vom Auftrag

Testlauf wurde wie verlangt ausgeführt, konnte jedoch durch die Sandbox-Sperre
keine Tests starten. Daher kein bestandener Unit-Testnachweis.
