# PL1 – Arbeitszeitplanung: Lücken gegenüber der PWA, Planfreigaben, Planungsbereich (macOS und iOS)

Branch `pl1-work-planning` (Worktree `timetrack-apple-wt/pl1`, von `main` Build 22). **Build-Nummer nicht erhöht, nichts hochgeladen, nicht gepusht.** Vertrag: Backend 0.25.0 (`/plan/weeks`, `/shares`, `/shares/incoming`).

Auftragsänderung während der Arbeit: Der Nutzer hat die Zeitplanung in der iOS-App gefunden; Z2 baut Zeit-Tab und Kalender um. Deshalb **keine neue Navigation auf iPhone/iPad**, `Sources/iOS/TimeView.swift`, `Sources/iOS/RootView.swift`, `AppSection` und die Kalender-Dateien (`Sources/Planning/*`) sind unverändert.

## 1. Inventur PWA gegen Swift-App

Quelle PWA: Routen `week`, `plan`, `shared`, `settings/sharing`, `vacation/planner`; Backend: `/plan/days`, `/plan/weeks/{isoWeek}`, `/time/weeks/{isoWeek}`, `/shares*`, `/vacation/suggestions`, `/work-models*`. Es gibt im Backend **keine** Plan-Vorlagen-Endpunkte (`import-templates` betrifft nur den Import) und keinen Mehrwochen-Schreibaufruf.

| Funktion | PWA | Swift vorher | Swift jetzt | Priorität / Bemerkung |
| --- | --- | --- | --- | --- |
| Wochenübersicht, Plan gegen Ist (`/week`) | ja | iOS (N1a, Z1 als Wochendetails) | unverändert, Mac: Code kompiliert jetzt, Einstieg über Planungsbereich nur Planer | Mac-Wochenübersicht als Seite: P3 (Folgepaket) |
| Wochenplaner: Modus, Beginn, Ende, Pause je Tag, Summen, Speichern, Schutz vor Verlassen | ja | iOS (N1a) | iOS + **Mac** (Planungsbereich) | erledigt |
| Standardwoche (Vorschlag aus 4 Wochen Historie), Vorwoche kopieren, „Alle gleich“, Leeren | ja | iOS (N1a) | iOS + Mac | erledigt |
| Tagesplan im Kalender (`/plan/days`) | ja | iOS + Mac (A10) | unverändert | erledigt |
| Blockierte Tage (Feiertag/Urlaub/krank) im Plan | ja | ja | ja | erledigt |
| Urlaubsplanung (`/vacation/planner`) | ja | iOS (N1a) | iOS + **Mac** (kompiliert, über Planungsbereich) | erledigt |
| **Planfreigaben anlegen/ändern/widerrufen** (`/settings/sharing`) | ja | **fehlte** | iOS + Mac | **P1, geschlossen** |
| **Geteilt mit mir** ansehen (`/shared`): Plan, tatsächliche Zeiten, Urlaub, Zeitraumwahl, 404 = widerrufen | ja | **fehlte** | iOS + Mac | **P1, geschlossen** |
| Mehrwochenübersicht der Planung | nein (PWA plant Woche für Woche) | nein | **neu**: „Kommende Wochen“ (8 Wochen: geplant von Soll, offene Tage, Tippen öffnet die Woche im Planer) | P2, geschlossen (über die PWA hinaus) |
| Planungsbereich als eigener Einstieg | Navigation „Woche“/„Plan“ | iOS: nur über Wochendetails/Kalender-Menü; Mac: fehlte ganz | **Mac-Seitenleiste „Arbeitszeitplanung“**; iOS: Menü im Wochenplaner (Z2-sicher) | siehe Entscheidung |
| Vorlagen (benannte Pläne) / Plan auf mehrere Wochen schreiben | **nein** | nein | nein | nicht umgesetzt: weder Backend noch PWA bieten es. Vorschlag Backend: `PUT /plan/weeks` für mehrere Wochen oder Plan-Vorlagen (Frage 1) |
| Konflikt-/Plausibilitätshinweise im Plan (Ende vor Beginn, Pause) | ja | ja | ja | erledigt |
| Arbeitsmodelle (Verlauf, Korrektur mit Vorschau) | ja | iOS + Mac (N1b) | unverändert | erledigt |
| Plan-Freigaben in Berichten/Exports | n. a. | n. a. | n. a. | – |

## 2. Entscheidungen

- **Mac**: `Sources/Week` ist für macOS portierbar. Es gab nur drei iOS-APIs (`navigationBarTitleDisplayMode`), jetzt mit `#if os(iOS)` gekapselt; `Sources/Week` gehört nun auch zum Mac-Target (`project.yml`). Neue Seitenleistenzeile **„Arbeitszeitplanung“** (Gruppe Planung, vor Kalender, Modul `planning`; fällt bei abgeschaltetem Modul auf „Heute“ zurück). Tastaturkürzel „Gehe zu“ ⌘1–5 folgen der Reihenfolge, daher ist Kalender jetzt ⌘4 und Urlaub ⌘5 (Planung ⌘3).
- **iOS**: keine neue Registerkarte und kein neuer Eintrag in der Seitenleiste (Auftrag, Z2). Der Planungsbereich ist über das Menü (Punkte-Symbol) im Wochenplaner erreichbar: „Kommende Wochen“ und „Freigaben“. Ein fester Einstieg im neuen Zeit-Tab bleibt Aufgabe von Z2: `PlanningHubScreen()` (Kommende Wochen, Urlaub planen, Freigaben) und `SharingScreen()` sind fertige, eigenständige Ziele.
- **Zeichenketten**: neue Tabelle `Sources/Week/PlanningArea.xcstrings` (Zugriff `PA.s/PA.t`), gemeinsam für iOS und Mac. Die 166 `wk.*`-Schlüssel der N1a-Views mussten dafür einmalig in `Sources/Mac/Localizable.xcstrings` kopiert werden (Mac nutzt die Views jetzt); künftige `wk.*`-Änderungen in beiden Katalogen pflegen.
- **Kommende Wochen** lädt 8 Wochen parallel (`GET /plan/weeks/…`), ein Fehler einer Woche blendet nur diese Zeile als „Nicht geladen“ aus. „Geplant“ = Tag mit gespeichertem Plan (Modus „frei“ zählt), nur Arbeitstage ohne Feiertag/Abwesenheit sind planbar.
- **Wechsel mit ungespeichertem Plan**: Tippen auf eine andere Woche fragt mit demselben Dialog wie der Planer (Verwerfen / Weiter bearbeiten).
- **Freigaben**: Eingabeprüfung lokal (Name fehlt, eigenes Konto, kein Umfang) vor dem Senden, Servercodes `recipient_not_found`, `share_exists`, `cannot_share_with_self` mit deutschem Text; Umfang pro Freigabe einzeln schaltbar (Aufruf je Schalter, bei Fehler Neuladen); Widerruf mit Rückfrage, wirkt sofort; 404 beim Ansehen entfernt die Freigabe aus der Liste. Hinweiskasten „Das wird nie geteilt“ wie in der PWA.
- Zeitraum der geteilten Ansicht: Standard heutige Woche plus 27 Tage (wie PWA).

## 3. Dateien

Kern: `Models/Sharing.swift`, `Planning/PlanHorizon.swift` (Zeile, Abdeckung, Formularprüfung), `Networking/APIClient.swift` (6 Aufrufe), `Models/APIError.swift` (3 Codes), Kern-Katalog (3 Texte), `TimetrackStores/Weeks/PlanHorizonStore.swift`, `SharingStore.swift`. App: `Sources/Week/PlanningArea.swift`, `SharingViews.swift`, `PlanningArea.xcstrings`, geändert `WeekHub.swift` (Cache, `WeekPlannerScreen(monday:showsAreaMenu:)`), `WeekPlannerView.swift` (eine Zeile), `VacationPlannerView.swift` (`#if os(iOS)`), Mac: `TimetrackMacApp.swift` (`SidebarItem.planning`), `RootView.swift`, `Localizable.xcstrings`. Seed: `scripts/seed-throwaway.py` legt das Konto „ben“ mit Freigabe (Plan, Urlaub) an alex an.

## 4. Tests und Belege

475 Kerntests grün (vorher 462; 13 neu in `PlanningAreaTests.swift`: Dekodierung Freigaben/geteilte Ansicht mit fehlenden Umfängen und unbekanntem Modus, Abdeckung unplanned/partial/complete, blockierte Tage, Wochenmontage über den Jahreswechsel, Formularprüfung, Servercodes mit deutschem Text, Wochenübersicht mit Teilfehler und 404, Freigabe anlegen/Umfang schalten/widerrufen, Fehlercode `share_exists`, geteilte Ansicht mit 404 = verschwindet, ungültiger Zeitraum sendet nichts), Design 31 grün. Builds macOS, iOS (Simulator), watchOS grün (unsigniert). UI-Tests gegen Wegwerf-Backend (iPhone 18 Pro, Port 18742): neu `PlanningAreaTests` (Kommende Wochen → Woche im Planer öffnen; Freigabe anlegen mit Prüfung, Umfang schalten, geteilte Ansicht von „ben“ zeigt nur Planung, Widerruf) **2/2 grün**; bestehende `WeekVacationTests` **2/2 grün**. Nicht erneut gelaufen: übrige UI-Tests (nur `Sources/Week` berührt). Bilder: `docs/screenshots/pl1-iphone-{weeks,shares,shared-view}.png`. **Nicht gesichtet:** Mac-Oberfläche (nur gebaut), iPad. Seed `scripts/seed-throwaway.py` legt zusätzlich Konto „ben“ mit Freigabe an.

## 5. Offen / Fragen

1. **Mehrwochen-/Vorlagenplanung** (Plan auf mehrere Wochen schreiben, benannte Vorlagen): Backend und PWA bieten es nicht. Soll das Backend dafür erweitert werden (Vorlage = Standardwoche mit Modi/Zeiten, Anwenden auf n Wochen in einer Transaktion)? Bis dahin ist „Kommende Wochen“ plus Vorwoche kopieren der Weg.
2. Fester iOS-Einstieg „Planung“ nach Z2 (Zeit-Tab/Kalender): `PlanningHubScreen` einhängen und das Menü im Planer ggf. entfernen.
3. Mac: Wochenübersicht (Plan gegen Ist, `WeekOverviewView`) kompiliert jetzt für den Mac, hat aber noch keinen Einstieg (nur Planer und Urlaubsplanung im Planungsbereich). Aufnehmen als weitere Zeile?
4. Geräteprüfung der Mac-Seitenleiste und der Freigabe-Ansichten steht aus (Mac nur gebaut, Fensterbild ohne Seitenleiste, siehe AD1).
5. Freigabe: Kontoname wird exakt eingegeben (kein Kontaktverzeichnis); Empfängersuche gibt es im Backend nicht.
