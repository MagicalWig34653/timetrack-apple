# N4 – Betriebstage 24.12./31.12. (Apple-Apps)

Stand: 26.10.2026, Branch `n4-company-days` (von `main` ba43a66). Backend-Vertrag 0.32.0, ADR-0029, Übergabe `N4-backend.md` im Backend-Repo.

## Umgesetzt

- **Kern** (`Models/CompanyDays.swift`): `CompanyDayTreatment` (none/half/full, unbekannte Werte bleiben beim Zurückschreiben erhalten), `CompanyDayRule`, `CompanyDayRules` (24.12./31.12. immer vorhanden, höchstens 12 Regeln, 29.02./doppelte/ungültige Daten, Name höchstens 80 Zeichen). `VacationSettings.companyDays` (nil = nicht senden, PUT lässt die Liste dann unverändert), `TimeWeekDay.holidayName`/`companyDayTreatment`/`holidayLabel`, `CalendarDay.companyTreatment`/`isHalfDay`/`displayName` ("Heiligabend (halber Tag)").
- **Einstellungen** (Urlaubseinstellungen, iOS/iPadOS/macOS): Abschnitt „Betriebstage“ mit Auswahl Keine/Halber Tag/Ganzer Tag für Heiligabend und Silvester, eigene Tage (Datum Tag.Monat., Name, Behandlung) hinzufügen/entfernen; lokale Prüfung, Serverfehler (400) erscheinen im bestehenden Fehlerbanner.
- **Anzeige**: Monatsraster/Kalender (Name mit Zusatz, voller Tag färbt die Zahl wie Feiertag, halber Tag nur Punkt), Tagesdetail („Halber Tag, halbes Soll“), Wochenansicht (Tageskopf mit Feiertagsname), Heute (Zeile mit Name unter dem Soll-Satz, bei jedem Laden aus `/calendar/holidays`).
- Texte in `Sources/Common/UX3.xcstrings` (Schlüssel `n4.*`).

## Prüfung

- `swift test --build-system native --no-parallel` im Kernpaket: 807 Tests grün (+11 in `CompanyDayTests`: Dekodierung, Settings-Round-Trip mit unbekannter Behandlung, PUT ohne Feld, Wochentag-Felder, Halbtag-Anzeige, Regelprüfung).
- Unsignierte Builds iOS (Simulator), macOS und watchOS grün.

## Nicht geprüft / offen

- Keine Bildschirmfotos, kein UI-Test, kein Lauf gegen ein Backend 0.32.0 (nur Dekodierung gegen Vertragsform).
- Kalender-Sync (EventKit) schreibt keine Feiertage, nur Pläne und Abwesenheiten; Titel wie „Heiligabend (halber Tag)“ liefert der ICS-Feed des Servers. Urlaubsplaner-Vorschläge zeigen nur den Namen aus `/vacation/suggestions` (kein Behandlungsfeld im Vertrag).
- Macs „Zeit“-Ansicht hat keine Wochendaten, daher dort keine Namenszeile je Tag (Kalender/Heute/Einstellungen vorhanden).
- Kein Merge, kein Build-Hochzählen, kein TestFlight (Lead).
