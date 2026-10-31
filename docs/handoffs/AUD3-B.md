# AUD3-B – Parität mit der PWA: Orte, halber Betriebstag, Urlaubsantrag

Branch `aud3-b` (Worktree `timetrack-apple-wt/aud3-b`) von `main` (Build 58). Nicht gemergt, nicht gepusht, nichts hochgeladen, Build-Nummer unverändert. Vertrag 0.39.0. Commits: `git log --grep "AUD3-B"`.

## Teil 1 – Archivierte Orte
- Kern: `APIClient.listPlaces(archived:)` (`GET /places?archived=true|all`, Enum `PlaceArchiveFilter`) und `restorePlace(id:)` (`POST /places/{id}/restore`). `PlaceArchiveSupport`: 400/404 bedeutet „Server vor 0.39.0“, andere Fehler (Netz, 5xx) verstecken die Funktion nicht; `archivedOnly` filtert die Antwort eines alten Servers, der den Parameter ignoriert und aktive Orte liefert, damit nie „Wiederherstellen“ für einen aktiven Ort erscheint.
- `AutomationStore`: `archivedPlaces`, `archiveSupported` (nil = unbekannt, false = ausgeblendet), `loadArchived()`, `restore(_:)` (Ort wandert in die aktive Liste, Engine plant die Regionen neu; bei 404 wird die veraltete Zeile entfernt). Nach `archive(_:)` wird das Archiv nachgeladen, wenn es unterstützt ist.
- Oberfläche: iOS „Standortautomatik“, Abschnitt „Archivierte Orte“ (aufklappbar, Knopf „Wiederherstellen“ je Ort, VoiceOver-Label mit Ortsname); Mac-Einstellungen: gleicher Abschnitt. Abschnitt erscheint nur, wenn der Server das Archiv kennt. Alte Hinweise „zurückholen lässt sich ein Ort derzeit nicht“ ersetzt.
- Nicht angefasst: die Einstellungsbildschirme von AUD3-A (Trigger-Links, Konto-Sicherheit, Profil); die Orte-Verwaltung liegt in `Sources/Location/AutomationSettingsView.swift` und `Sources/Mac/Settings/AutomationSettingsView.swift`.

## Teil 2 – Halber Betriebstag (ADR-0029)
Bestand vor AUD3-B: Kern dekodiert `holidayName`, `companyDayTreatment` (Woche), `companyTreatment` (Kalender); Monatsraster, Tagesdetail und Wochenzeile zeigten den Namen mit „(halber Tag)“. Soll und Urlaubsabzug berechnet der Server (halbes Soll, höchstens halber Urlaubstag), die App rechnet nichts nach.
Neu:
- Kern: `HolidayNote` (Name, Behandlung, `badge` „Heiligabend ½“, `hint` wie PWA-`holidayHint`: „… – halber Betriebstag, Soll halbiert“), `HolidayNote.notes(from:in:)` (sieben Tage ab Montag, nur Art Feiertag, ein voller Feiertag schlägt einen halben Betriebstag am selben Datum), `CompanyDayText.hint`.
- `WeekPlanStore.holidayNotes`: best effort aus `GET /calendar/holidays?year=` (je Jahr gecacht, Fehler lassen den Planer unverändert).
- Wochenplaner (`PlanGridView`): Kopfzeile eines halben Betriebstags zeigt Chip mit Flagge, „½“ und gestricheltem Rahmen (nicht nur Farbe), gesprochener Hinweis; der Tag bleibt planbar. An gesperrten Feiertagen steht der Feiertagsname statt des allgemeinen „Feiertag“; Spaltenlabel enthält den Hinweis.
- Wochenliste (`DayKindPill`): halber Betriebstag mit „½“, Flaggensymbol, gestricheltem Rahmen und gesprochenem Hinweis.
- Urlaubsplaner (Vorschläge): unverändert, der Server wertet nur `full` als Feiertag (Vertrag).

## Teil 3 – Urlaubsantrag aus der Jahresübersicht
Bestand (AB1): Antrag-PDF wird nativ mit PDFKit gefüllt (Vorschau, Teilen, Sichern, Drucken, als Anhang speichern), erreichbar über Zeilenmenü der Abwesenheit. Neu:
- Jahresübersicht (Urlaub-Tab, iOS und Mac): Karte „Urlaubsantrag erstellen“ mit Menü der Urlaube des Jahres (Zeitraum, Status), öffnet das bestehende Antragsblatt; ohne passenden Urlaub deaktiviert mit Erklärung.
- Urlaubsplaner (iOS): nach „Übernehmen“ je angelegtem Urlaub ein Knopf „Urlaubsantrag erstellen“ (wie PWA); `VacationPlannerStore.createdAbsences`.
- Regel wie PWA: Antrag nur für Urlaub, der nicht storniert/abgelehnt ist (`VacationRequestEligibility`); gilt jetzt auch im Zeilenmenü.
- **Lücke:** Die Vorlage (Arbeitgeber-PDF hochladen und Felder zuordnen, PWA `settings/vacation-form` mit PdfCanvas/BindingPicker) ist nativ nicht gebaut; die App verweist wie bisher auf die Web-App („Vorlage richtest du in der Web-App ein“). Das Zuordnen per Klick auf eine PDF-Seite wäre ein eigenes Paket (PDFKit-Seitenansicht, Bindungsliste, Größenregeln des Servers).

## Tests und Builds (tatsächlich gelaufen)
- `swift test` in `Packages/TimetrackCore`: 953 Tests in 132 Suites grün (Stand vor AUD3-B 938; +8 `PlaceArchiveTests`, +5 `HolidayNoteTests`, +2 `VacationRequestEligibilityTests`, +1 Erwartung in `WeekVacationTests`).
- `xcodebuild` ungesigniert, eigenes DerivedData (parallele Builds anderer Agents sperren die Standard-Datenbank): Schema TimetrackIOS (iOS-Simulator) BUILD SUCCEEDED, Schema TimetrackMac BUILD SUCCEEDED. watchOS nicht gebaut (nicht berührt).

## Nicht geprüft
- Keine UI-Tests, keine Simulator-Sichtprüfung der neuen Abschnitte/Chips (nur gebaut); Layout des Planer-Kopfes mit 88 pt bei großer Schrift ungeprüft.
- Archiv und Restore nur gegen den Mock-Transport, nicht gegen ein echtes Backend 0.39.0.
- Gerät, VoiceOver-Ausgabe, Mac-Oberfläche ungeprüft.
