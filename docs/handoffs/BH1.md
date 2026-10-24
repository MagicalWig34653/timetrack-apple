# BH1 – Berichtsheft nativ (iPhone, iPad, Mac)

Branch `bh1-berichtsheft` (Worktree `timetrack-apple-wt/bh1`) von `main` (Build 38). Nicht gemergt, nicht gepusht, nichts hochgeladen, Build-Nummer unverändert. Nur Claude. Watch bewusst ohne Berichtsheft.

## Grundlage (Vertrag 0.27.0, ADR-0008, PWA `/reports`)
Endpunkte unter `/reports`: Lernfelder (GET/POST/PUT/DELETE), Einträge (POST, PUT mit `If-Match`=version, DELETE), Woche (`GET/PUT /reports/weeks/{year}/{week}`, Status draft/done), Text (`/text`, text/plain), Quellen (Notiz oder Datei über `POST /files`). **Nicht vorhanden:** KI-Entwurfsendpunkt (nur das Feld `draft` an Einträgen, die App zeigt „KI-Entwurf“, erzeugt aber keine) und jeder PDF-/Datei-Export des Berichtshefts. Beides wurde deshalb nicht gebaut.

## Umgesetzt
| Bereich | Inhalt | Dateien |
| --- | --- | --- |
| Kern | Modelle (`LearningField`, `ReportEntry`, `ReportWeek`, `ReportSource`, `ReportWeekRef` mit ISO-Wochen über den Jahreswechsel inkl. KW 53), Dauer-Eingabe wie PWA (`1:30`, `1,5`, `2`; 7,7 = 7:42), Text-/HTML-Ausgabe im Standardformat (Spiegel des Server-Formats, offline nutzbar), API-Aufrufe inkl. Multipart-Upload `POST /files`, Fehlercodes `learning_field_exists`, `file_too_large`, `unsupported_type` | `Models/Reports.swift`, `Support/ReportText.swift`, `Networking/APIClient.swift`, `APIError.swift`, Kern-Katalog |
| Stores | `ReportsStore` (Woche laden/wechseln, lokales Zusammenführen und Neuberechnen der Summen, Status, Lernfelder, Quellen, Kopier-Inhalt: Server-Text, bei Netzfehler lokal gebaut); `ReportEntryEditor` (Autosave mit Entprellung 0,9 s, Anlegen erst mit Lernfeld, Zustände idle/pending/saving/saved/invalid/failed/conflict/gone) | `TimetrackStores/ReportsStore.swift`, `ReportEntryEditor.swift` |
| Oberfläche (iOS und Mac geteilt) | Wochenansicht (Wochenleiste, Status, Summen je Lernfeld, Hinweis Arbeitszeit der Zeiterfassung, Tageskarten mit Hinzufügen, Kontextmenü/Löschen), Editor-Sheet (Datum, Lernfeld frei oder aus Liste, Zeit mit Live-Lesehilfe, Notizen mit Zähler, Status „Gesichert“), Lernfelder (Liste, Sortieren, Nummer, Löschen mit Hinweis), Quellen (Notiz je Tag/Woche, Datei per Importer, QuickLook), Kopier-Sheet (Vorschau, Kopieren: Klartext plus HTML-Tabelle in der Zwischenablage, Teilen) | `Sources/Reports/*`, Katalog `Reports.xcstrings` (Tabelle „Reports“) |
| Einstiege | iOS: Mehr › Gruppe „Ausbildung“ › Berichtsheft (ersetzt die Zeile „Im Web“, die nur noch Auswertung/Export enthält); Zeit › Menü „Berichtsheft für diese Woche“ (öffnet die angezeigte Woche). Mac: Seitenleistenpunkt Berichtsheft (⌘6), Menü Zeit › Berichtsheft für diese Woche (⌥⌘B), Symbolleistenknopf in „Zeit“, Kürzel ⌘⇧C kopieren, ⌘⇧N neuer Eintrag, ⌥⌘←/→ Woche, ⌘⇧T aktuelle Woche | `MoreView.swift`, `TimeHub.swift`, Mac `TimetrackMacApp/RootView/MacCommands/TimeView` |
| Barrierefreiheit | Einträge als ein Element mit gesprochenem Satz, Aktion „Löschen“ als Custom Action, 44-pt-Ziele, Dynamic Type (Zweispalten nur bei normaler Schriftgröße und Breite ≥ 820 pt, sonst eine Spalte), Fehler/Status mit Text und Symbol |  |
| Glossar | Berichtsheft, Lernfeld, Quellen; „Mehr“ aktualisiert | `docs/glossary-ui.md` |

## Entscheidungen
- **Autosave/Offline:** Das Backend hat keine Schreib-Warteschlange für Berichte, und die App kennt sonst kein Offline-Schreiben. Deshalb: Eingaben bleiben im Editor erhalten, Fehlerzustand mit „Erneut versuchen“; Schließen speichert zuerst, bei Misserfolg fragt ein Dialog (Weiter bearbeiten/Verwerfen). Nicht persistent über App-Neustart. 412 → Wahl „Aktuelle Fassung laden“/„Meine Eingabe trotzdem sichern“; 404 → „Als neuen Eintrag sichern“.
- Dateien: Uploadtypen entscheidet der Server (413/415 werden angezeigt).

## Tests und Prüfung
- Kerntests: 589 grün (neue Datei `ReportsTests.swift`: Wochenrechnung, Dauerparser, Textformat, Store, Editor inkl. Entprellung, Offline, 412, 404, Upload). `MockTransport.set` kann jetzt auch Fehler.
- Builds iOS, macOS, watchOS (unsigniert): grün.
- UI-Test `Tests/iOSUI/ReportsTests.swift` (Mehr › Berichtsheft, neuer Eintrag mit Autosave, Kopier-Sheet, Lernfelder) auf iPhone-18-Pro-Simulator mit Wegwerf-Backend (Seed: Lernfelder, vier Einträge, eine Quelle): grün. Bilder: `docs/screenshots/bh1-iphone-{week,editor,copy,fields}.png`.
- Nach Sichtung geändert: Kopier-Sheet nur noch `.large` (Text war bei `.medium` abgeschnitten).

## Nicht geprüft / offen
- **iPad-Aufnahme und Mac-Fenster nicht gesehen:** iPad-Lauf hing bei hoher Maschinenlast, der Mac-Debug-Hook schrieb ohne Fenster keine Bilder (kein Bildschirmzugriff im Hintergrund). Zweispaltiges Layout, Mac-Sidebar, Menükürzel nur gebaut.
- VoiceOver-Durchlauf, Dateivorschau mit echten Dateien, Dateiupload gegen echtes Backend (nur Mock-Test des Multipart-Aufbaus), Gerät mit OS 27.
- Offene Frage: Soll das Berichtsheft auf dem iPad in die Seitenleiste (nicht nur Mehr)?
