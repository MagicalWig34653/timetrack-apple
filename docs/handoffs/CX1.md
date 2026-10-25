# CX1 – UI-Tests, Strings, Tagesdifferenzen und Timer-Warteschlange

Branch `cx1-cleanup`; Änderungen bleiben uncommitted. Grundlage: Backend `main`, Vertrag unverändert, UX3/Z3/X2 sowie SG1/BH1.

## Änderungen

- `AutomationFlowTests`: eigenes synthetisches Seed `seed-cx1.py` mit „Büro Test“ und festen Positionen; der neue Ort verwendet im Debug-Lauf eine feste Kartenkoordinate. Die Seite wird weiterhin über Mehr geöffnet.
- `ParityFlowTests`: die Arbeitsmodell-Vorschau ist als eigenes Accessibility-Element erreichbar; nach dem Speichern wird die Navigation über Mehr › Einstellungen neu geöffnet, bevor „Über Timetrack“ geprüft wird.
- `VoidSegmentTests`: Wochenzoom und der vorherige, vollständig vergangene Seed-Wochenbereich statt einer von Wochentag und Uhrzeit abhängigen aktuellen Woche. Der CX1-Seed ergänzt drei eindeutige Einträge; „Berufsschule“ stammt aus dem Grundseed.
- `SmokeTests`: Start/Stopp über die aktuelle Jetzt-Leiste; für den Lauf ist `seed-throwaway.py --no-today` vorgesehen, damit keine künftigen Einträge des heutigen Tages einen frühen Timerstart beeinflussen. Monat im Zeit-Tab wird fest eingestellt.
- `DayHeader` im Zeit-Wochenzoom verwendet `DayDeltaPolicy` für neutrale offene Zeit heute und Warnfarbe nur für vergangene Defizite.
- Die iOS-App verbindet `TodayStore` mit der vorhandenen persistenten Timer-Warteschlange. Auf Heute erscheint ein Hinweis, der ein Blatt mit Konfliktgrund, „Verwerfen“ und „Erneut versuchen“ öffnet. Ein erneuter Versuch behält die ursprüngliche Ereignis-ID; ein wiederholter Konflikt bleibt sichtbar. Kern-Tests decken diese Wiederholung und die Wiederherstellung nach Anmeldung ab.

## Prüfungen

- `swift test --build-system native --disable-sandbox --scratch-path .build-cx1 --cache-path /private/tmp/cx1-swiftpm-cache` im Core-Paket: **757 Tests in 103 Suites grün**. Zusätzliche Cache-Umgebungsvariablen waren wegen der Sandbox nötig.
- `xcrun swiftc -frontend -parse` für die geänderten iOS-, UI-Test- und Week-Dateien: grün.
- iOS-, macOS- und watchOS-Builds wurden mit `-derivedDataPath ./.dd` und `CODE_SIGNING_ALLOWED=NO` versucht. Alle drei stoppen vor der Kompilierung bei der Paketauflösung, weil Xcode in gesperrte SwiftPM-/Clang-Caches im Benutzerverzeichnis schreiben will (`Operation not permitted`). Die Builds sind **nicht als grün belegt**.
- `xcrun simctl list devices booted` scheitert am nicht erreichbaren CoreSimulatorService. UI-Tests konnten deshalb nicht laufen.
- Ein lokaler Wegwerf-Backend-Start aus dem vorhandenen `main`-Build wurde versucht. Die Sandbox verweigert bereits den Loopback-HTTP-Zugriff (`Operation not permitted`); Seed und UI-Integration sind hier nicht verifiziert. Ein eigenes Backend-Build war deshalb nicht zielführend. Der dabei gestartete Prozess ist beendet und das Wegwerf-Verzeichnis entfernt.
- `python3 -m py_compile` für die Seed- und Audit-Skripte, `git diff --check`, Katalog-JSON-Parse: grün.

## String-Kataloge

`scripts/audit-strings.py` vergleicht Katalogschlüssel mit Swift-Quellen in `Sources/` und den verwendeten Paketen. Zusammengesetzte `wk.`-Schlüssel, interpolierte Schlüssel und Pluralformen werden berücksichtigt. 88 unbenutzte Einträge wurden entfernt; ein erneuter Lauf meldet keine Kandidaten. Der erste Durchlauf entfernte 30 bestätigte Einträge: `ux3.now.open_today`, `ux3.sheet.details` und je in iOS/Mac `wk.segment.list`, `wk.segment.week`, `today.delta`, `today.of_target %@`, `time.week_range %@ %@`, `time.week_total %@ %@` sowie die acht `vacation.tile_*`-Einträge. `wk.segment.plan` bleibt: Der Wochenplaner verwendet ihn noch. Der generierte Restbericht vor dem zweiten Entfernen lautet:

```text
Sources/Mac/Localizable.xcstrings (21 candidates)
  menubar.quit
  menubar.reload
  plan.action.custom_day
  plan.action.segment
  signin.title
  vacation.balance_formula
  vacation.booked
  vacation.carry_over
  vacation.edit_entitlement
  vacation.planned
  vacation.snapshot_row %@
  wk.aria.balance
  wk.aria.hours
  wk.aria.planned
  wk.detail.link
  wk.detail.title
  wk.empty.plan
  wk.sum.actual
  wk.sum.actual_hint
  wk.week.empty_text
  wk.week.empty_title
Sources/Planning/Vacation.xcstrings (2 candidates)
  attachments.show
  filter.section_filter
Sources/Suggestions/SG1.xcstrings (10 candidates)
  sg1.adjust.title
  sg1.cancelled.group
  sg1.cancelled.group.footer
  sg1.cancelled.hint.restore %@
  sg1.cancelled.row
  sg1.cancelled.select_none
  sg1.more.footer
  sg1.more.group
  sg1.more.row
  sg1.review.title
Sources/Week/PlanningArea.xcstrings (3 candidates)
  hub.menu
  hub.menu.shares
  hub.menu.weeks
Sources/WidgetShared/Widget.xcstrings (2 candidates)
  w.live.of_planned %@
  w.live.since %@
Sources/iOS/Localizable.xcstrings (20 candidates)
  plan.action.custom_day
  plan.action.segment
  signin.title
  time.overview
  vacation.balance_formula
  vacation.booked
  vacation.carry_over
  vacation.edit_entitlement
  vacation.planned
  vacation.snapshot_row %@
  wk.aria.balance
  wk.aria.hours
  wk.aria.planned
  wk.detail.link
  wk.detail.title
  wk.empty.plan
  wk.sum.actual
  wk.sum.actual_hint
  wk.week.empty_text
  wk.week.empty_title
```

## Offene Prüfung außerhalb der Sandbox

Mit einem beschreibbaren Xcode-/SwiftPM-Cache und einem erreichbaren Simulator: iOS/macOS/watchOS-Builds wiederholen; `AutomationFlowTests`, `ParityFlowTests` und `VoidSegmentTests` mit `seed-cx1.py`, `SmokeTests` mit `seed-throwaway.py --no-today` gegen einen frisch gebauten Backend-`main`-Wegwerfserver ausführen. Danach die globale Ergebniszeile im Backend-Projektgedächtnis ergänzen; die Sandbox erlaubt hier keine Backend-Dateischreibzugriffe.
