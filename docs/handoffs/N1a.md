# N1a – Wochenübersicht, Wochenplanung, Urlaubsplanung (iOS/iPadOS)

Branch `n1a-week-vacation` (Worktree `timetrack-apple-wt/n1a`). **Build-Nummer nicht erhöht, nichts hochgeladen, nicht gepusht.** Vertrag: Backend 0.23.0 (K1/ADR-0021, V2/ADR-0025). Referenz: PWA-Routen `week`, `plan`, `vacation/planner`.

## Umfang
- **Kern** (`Packages/TimetrackCore`): Modelle `TimeWeek`, `PlanWeek`, `PlanWeekInput`, `VacationSuggestions` (unbekannte Enum-Werte werden `.unknown`, nie Dekodierfehler); `PlanDay`/`PlanDayInput` um `plannedStart/End/BreakMinutes/plannedSeconds` erweitert; `APIClient.getTimeWeek/getPlanWeek/putPlanWeek/getVacationSuggestions`; reine Logik `IsoWeek`, `WeekPlan` (Entwurf, Prüfung, Standardwoche, Kopieren, „Alle gleich“, Leeren, Vorschlagsfenster), `WeekOverview`, `VacationPlanner` (Filter, Blöcke, Konfliktgruppen, Tagesstreifen); Stores `WeekStore`, `WeekPlanStore`, `VacationPlannerStore` (`Sources/TimetrackStores/Weeks`).
- **App** (`Sources/Week`, nur iOS-Target): Zeit-Tab bekommt eine Segmentwahl Liste | Woche | Planen (Planen nur bei Modul `planning`); Urlaub-Tab bekommt oben die Karte „Urlaub planen“ (`#if os(iOS)` in `VacationScreen`) mit Push auf die Urlaubsplanung. macOS: unverändert, baut.
- Texte: Schlüssel mit Präfix `wk.` in `Sources/iOS/Localizable.xcstrings` (Hilfsfunktion `W.s/W.t`); Fehlertexte im Kern-Katalog.

## Entscheidungen
- **PUT ersetzt den Tag**: Der Kalender-Plansheet (A10) sendet jetzt gespeicherte Zeiten mit; sonst hätte er geplante Zeiten aus der Wochenplanung gelöscht. `PlanDayInput(keeping:)` als Hilfe.
- **Wochenplan-PUT** mit `replace=true`; blockierte Tage (Feiertag/Urlaub/krank) mit gespeichertem Plan werden unverändert wieder mitgesendet (sonst gelöscht). Zeiten nur bei Arbeitsmodus mit beiden Zeiten; „Aus“ sendet keine Zeiten.
- **Schutz vor Verlassen mit Änderungen**: Wechsel der Woche im Planer fragt per Dialog (Verwerfen / Weiter bearbeiten). Die Stores liegen in einem Cache (`WeekStoreCache`), daher geht ein Entwurf beim Wechsel von Segment oder Tab nicht verloren; er erscheint bei Rückkehr weiter als „Ungespeicherte Änderungen“. Ein echtes Abfangen des Tabwechsels gibt es nicht (SwiftUI-`TabView`).
- **Übernehmen**: ein geplanter (`planned`) Urlaub je zusammenhängendem Block (Regel wie PWA: nur bereits eingetragene Urlaubstage trennen Blöcke) über `POST /absences`. Bestätigung mit Pflichtkästchen bei Konflikten (Berufsschultag, Abwesenheit, Arbeit geplant) und bei Budgetüberschreitung; ohne Kästchen sendet der Store nichts (getestet). **Abweichung von der PWA:** „schon als Urlaub eingetragen“ ist nur Hinweis, braucht kein Kästchen (kostet nichts). Teilerfolg (Block 2 scheitert) wird gemeldet, danach Neuladen.
- **503 `database_unavailable`**: Im Client gab es bisher kein Retry-Verhalten. Neu: Lesezugriffe werden bis zu 2 Mal nach `Retry-After` wiederholt (Wartezeit auf 10 s gedeckelt, Standard 2 s); Schreibzugriffe werden nie automatisch wiederholt (unklar, ob verarbeitet), der Fehler hat deutschen Text und die Bildschirme bieten „Erneut versuchen“.
- Filter der Urlaubsplanung (Zeitraum, max. Urlaubstage, min. freie Tage, Faktor ab 2, Anzahl) lokal in UserDefaults; Faktor und Anzahl filtern nur die Anzeige, der Server wird immer mit Limit 100 gefragt.
- Konflikte blenden nie aus: Karte mit Warnrahmen, Warnblock und Markierung im Tagesstreifen (Symbol + Text zusätzlich zur Farbe).

## Tests
- Kern: `WeekVacationTests.swift` (Dekodierung mit Fixtures aus V2-Handoff/Vertrag, Wochenplan-Logik, Blöcke/Konflikte/Streifen, Filter, Stores, Retry-After). Gesamt siehe STATUS.
- UI (`Tests/iOSUI/WeekVacationTests.swift`, Wegwerf-Backend wie A10/F-Pakete): Woche → Planen → Standardwoche → Dialog beim Wochenwechsel → Speichern → Übersicht mit Plan; Urlaubsplanung → Filter → Karte → Bestätigung → Buchung. Bilder `docs/screenshots/n1a-*.png`.

## Grenzen / offen
- Gerät nicht geprüft; Haptik nur über bestehende `StoreOutcome`s.
- iPad: Zwei-Spalten-Raster der Tageskarten; Tabwechsel mit ungespeichertem Plan wird nicht abgefangen (siehe oben).
- Kumulative Budgetprüfung über mehrere Vorschläge (ADR-0025 offen) fehlt; Eingabe der Uhrzeiten über Standard-`DatePicker` (kompakt), Schritte nicht auf 15 Minuten beschränkt.
- Freigaben von Plänen (Backend 0.17) werden in der App noch nicht angezeigt.
