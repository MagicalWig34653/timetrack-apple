# AB1 – Anhänge an Abwesenheiten und Urlaubsantrag-PDF (iPhone, iPad, Mac)

Branch `ab1-attachments-vacation-form` (Worktree `timetrack-apple-wt/ab1`) von `main` (Build 40). Nicht gemergt, nicht gepusht, nichts hochgeladen, Build-Nummer unverändert. Nur Claude. Vertrag 0.24.0 (Anhänge) und 0.25.0 (Vorlage, ADR-0026). Referenz: PWA `src/lib/vacation-form/*`, `AbsenceAttachments.svelte`, Handoff P8. Behebt die Lücken „Anhänge hochladen/löschen“ und „Urlaubsantrag-PDF“ der Lückenliste PWA gegen Apple.

## 1. Anhänge (hochladen, ansehen, löschen)
Blatt „Anhänge“ (`AbsenceAttachmentsSheet`, vorher nur Ansicht aus V3), erreichbar über die Büroklammer der Zeile oder das Kontextmenü. Die Büroklammer steht jetzt in jeder Zeile (leer: `paperclip.badge.plus`).

| Weg | Umsetzung |
| --- | --- |
| Datei auswählen | `fileImporter` (PDF, PNG, JPG, HEIC, TXT; Mehrfachauswahl) |
| Dokument scannen | VisionKit `VNDocumentCameraViewController` (nur iOS/iPadOS, Zeile nur sichtbar, wenn die Kamera verfügbar ist, also nicht im Simulator); Seiten werden zu **einem PDF** (JPEG-komprimiert, Qualität 0,7) |
| Foto aus der Mediathek | `PhotosPicker`; jedes Format wird zu JPEG (längste Kante höchstens 3000 px, Qualität 0,8, EXIF-Ausrichtung angewandt), damit Handyfotos klein bleiben |
| Ziehen und Ablegen | `onDrop` auf dem Blatt (iPad, Mac), gestrichelter Rahmen als Rückmeldung; Hinweistext nur auf iPad/Mac |
| Ansehen | wie V3 (QuickLook, temporäre Datei, Dateischutz, wird beim Schließen gelöscht) |
| Löschen | Papierkorb je Zeile mit Rückfrage; löst die Verknüpfung (`DELETE /absences/{id}/attachments/{fileId}`) und löscht danach die Datei (`DELETE /files/{id}`, Best Effort wie PWA) |

Ablauf eines Uploads (`AbsenceAttachmentsStore`, Kern): lokale Prüfung (Whitelist wie PWA, nicht leer, harte Obergrenze 64 MiB gegen Speicherüberlauf) → `POST /files` (multipart, **mit Fortschritt** über `URLSessionTaskDelegate.didSendBodyData`, durchgereicht über `HTTPTransport.send(_:progress:)`) → `POST /absences/{id}/attachments`. Schlägt nur die Verknüpfung fehl, wird der verwaiste Upload gelöscht (wie PWA). Fehler stehen als Eintrag „Wird hochgeladen“ in der Liste und behalten die Daten im Speicher: **413 und 415 (auch ohne Fehlerrumpf, z. B. durch einen Proxy)** zeigen deutschen Text und bieten nur „Verwerfen“; Netzfehler bieten „Erneut versuchen“ ohne neue Auswahl. Das Serverlimit (Standard 10 MiB, Betreiber einstellbar) ist dem Client nicht bekannt; die App entscheidet bewusst nicht selbst, sondern zeigt die Antwort des Servers.
Neu im API-Client: `attachFile`, `detachFile`, `deleteFile`, Fortschritt bei `uploadFile`. `project.yml`: `NSCameraUsageDescription` (deutscher Text, Bilder bleiben bis zum Speichern auf dem Gerät).

## 2. Urlaubsantrag-PDF
Zeilenmenü (Büroklammer bei Urlaub, Kontextmenü/Langdruck) → „Urlaubsantrag erstellen“ → Blatt `VacationRequestSheet`. Ablauf wie der PWA-Dialog:
1. `GET /vacation/request-form` (`exists`, `mapping`), `GET …/file` (PDF), Urlaubskonto des Startjahres, Arbeitsmodelle und Feiertage aller Jahre des Zeitraums.
2. Anzeige Arbeitstage und Resttage vorher/nachher, Vertreter (nur im PDF, nicht gespeichert), freie Tage (Wochenenden, Feiertage, vom Arbeitsmodell freie Tage) zum Bestätigen mit Warnung, wenn das Formular weniger Plätze hat, „Nicht mehr bearbeitbar machen“ (flatten, Standard aus der Zuordnung).
3. „PDF erstellen“ füllt mit **PDFKit** auf dem Gerät (nichts verlässt es); Vorschau (`PDFView`), **Teilen**, **Sichern** (`fileExporter`, Dateien/iCloud Drive), **Drucken** (`UIPrintInteractionController` / `NSPrintOperation`), **Als Anhang speichern** (Upload und Verknüpfung mit der Abwesenheit, Zustand „Als Anhang gespeichert“, Büroklammer in der Liste aktualisiert sich).
4. Keine Vorlage (`exists == false` oder 404 auf die Datei): Erklärung und Link „Vorlage in der Web-Oberfläche einrichten“ (`<Server>/settings/vacation-form`).

**Was abgedeckt ist:** Erzeugen, Vorschau, Teilen/Sichern/Drucken, Anhängen. **Was bewusst fehlt:** Vorlage hochladen/ersetzen/entfernen und Zuordnung bearbeiten (Web-Oberfläche; eine einfache Zuordnungsoberfläche ist ohne Seitenvorschau mit Klickpositionen für flache PDFs nicht sinnvoll, die Zuordnung ist ein 64-KB-JSON mit 26 Quellen). Die App schreibt weder Datei noch Zuordnung auf den Server; die Endpunkte `PUT …/file`, `PUT …/mapping` und `DELETE` sind nicht im Client.

### Zuordnungssemantik (aus der PWA übernommen, `Packages/TimetrackCore/Sources/TimetrackCore/VacationForm/`)
- `FormMapping(json:)` liest defensiv wie `parseMapping`: unbekannte Quellen und kaputte Einträge fallen weg, Zahlen werden begrenzt (Bereichsnummer 1–8, Schrift 4–48, Seite ≥ 0, höchstens 200 Textpositionen), Feldnamen bis 256 Zeichen, Texte bis 500 (Person 200).
- 26 Quellen mit denselben IDs (Rohwerte) wie die PWA; Test vergleicht die Menge.
- Datum: `dd.MM.yyyy`, `d.M.yy`, `iso`; je Bindung überschreibbar; nicht lesbare Eingabe bleibt unverändert. Tage als deutsche Dezimalzahl in Halbtagen (`4,5`). Halbtage am Anfang/Ende ziehen 0,5 Arbeitstage ab (zählt bei Ein-Tages-Zeitraum einmal; nur wenn der Tag ein Arbeitstag ist). Freie Tage: Feiertag (Art `holiday`, Schulferien befreien nicht), Wochenende, Tag ohne Arbeitstag im Modell oder mit Tagessoll 0; ohne Modell Montag bis Freitag; gilt das Modell, das am Tag gültig ist (neuestes `validFrom`). Aufeinanderfolgende freie Tage werden zu Bereichen; „Anzahl freier Tage“ zählt Kalendertage aller Bereiche. Resttage: Stichtagsbestand ersetzt Anspruch und Übertrag; `restBefore = availableAfterPlanned + (Antrag schon im Konto ? Antragstage : 0)`.
- Leerer Wert löscht ein Textfeld (`setText(undefined)` der PWA); Auswahlfeld wird nur gesetzt, wenn der Wert eine Option ist (sonst „nicht gesetzt“-Hinweis); Kontrollkästchen an/aus; schreibgeschützte Felder, Unterschrift/Knopf/Liste bleiben unberührt. Textpositionen (Overlays) für flache PDFs: x/y als Grundlinie wie `pdf-lib drawText`; Seite außerhalb oder leerer Wert werden übersprungen.
- Hierarchische Felder: PDFKit liefert `Eltern.Kind` als Feldnamen, wie pdf-lib `getName()`; gleicher Schlüssel in der Zuordnung.

### Abweichungen von der PWA (bewusst oder technisch)
- Nicht „flatten“: Textpositionen sind **FreeText-Anmerkungen** (druckbar, auswählbar), in PDFKit gibt es kein Seiteninhalt-Zeichnen ohne Neuaufbau. Mit „Nicht mehr bearbeitbar machen“ wird jede Seite samt Feldern und Anmerkungen in ein neues PDF gezeichnet (Text bleibt als Text erhalten, im Test belegt).
- Textpositionen nutzen wie in der PWA Helvetica, schwarz. Umlaute in Textfeldern übernimmt PDFKit selbst; ob exotische Zeichen in Feldern mit fester Schrift fehlen, ist ungeprüft (die PWA meldet sie als „nicht gesetzt“, die App kann das nicht erkennen).
- Verschlüsselte PDFs: `isLocked` oder verschlüsselt ohne Änderungsrecht → Meldung „passwortgeschützt“.
- Feldkennungen: Nur Felder mit `fieldName` und Unterart Widget zählen; Optionsgruppen und Listenfelder sind „nicht ausfüllbar“ (wie PWA `other`).

## Dateien
Kern: `Models/VacationRequestForm.swift`, `VacationForm/FormMapping.swift`, `FormRequest.swift`, `FormPDF.swift`, `Support/AttachmentRules.swift` (Whitelist, Bildkomprimierung), `Networking/APIClient.swift` und `Transport.swift` (Fortschritt, 4 neue Aufrufe), `Models/APIError.swift` und `Localizable.xcstrings` (`no_template`, `mapping_too_large`), Stores `AbsenceAttachmentsStore.swift`, `VacationRequestStore.swift`, `PlanningStore.swift` (zwei Fabriken). App: `Sources/Planning/AbsenceAttachmentsSheet.swift` (ersetzt den V3-Abschnitt in `VacationTools.swift`), `VacationRequestSheet.swift`, `VacationScreen.swift` (Menü/Kontextmenü), Texte in `Vacation.xcstrings` (Tabelle „Vacation“), Glossar (Anhang, Urlaubsantrag). Tests: `VacationFormTests.swift`, `AbsenceAttachmentsTests.swift`, `SyntheticFormPDF.swift` (Hilfsgenerator, handgeschriebene PDF-Syntax), `Tests/iOSUI/AttachmentsRequestTests.swift`, `scripts/seed-ab1.py`.

## Datenschutz
Das leere Arbeitgeberformular wurde **nie** gelesen, kopiert oder eingecheckt. Alle Tests und Seeds nutzen selbst erzeugte, synthetische PDFs („Urlaubsantrag (synthetisch)“, Feldnamen erfunden). Der Seed erzeugt die Dateien im Scratch-Verzeichnis, nicht im Repo.

## Tests und Prüfung
- Kern: `swift test --build-system native` 704 grün (neu u. a. `FormFormatTests`, `FormMappingParsingTests`, `FormCalendarTests`, `FormResolveTests`, `FormPDFTests` mit PDFKit-Lauf über synthetische Formulare: Text, Kontrollkästchen, Auswahl, schreibgeschützt, Unterschrift, Elternfelder, mehrseitig, flatten, Overlays, kaputt/zu groß/verschlüsselt; `VacationRequestStoreTests` gegen Mock-Transport inkl. Anhängen und Aufräumen; `AttachmentRulesTests`, `ImageCompressorTests`, `AbsenceAttachmentsStoreTests` (413/415, Netzfehler mit Wiederholen, Verwaisen-Aufräumen, Löschen), `UploadProgressTests`).
- Builds iOS (unsigniert, Simulator) und macOS grün, watchOS siehe unten.
- UI-Test `AttachmentsRequestTests` (iPhone 18 Pro, Wegwerf-Backend Port 18771, `seed-throwaway.py` + `seed-vacation-v3.py` + `seed-ab1.py`): Antrag ausfüllen, Vorschau, „Als Anhang speichern“ (bestanden); zu große Datei (11 MiB) liefert Eintrag „zu groß“ ohne Wiederholen (bestanden); Hochladen, QuickLook, Löschen (bestanden). Systemauswahlen sind im UI-Test nicht bedienbar; die Debug-Variable `TT_DEV_ATTACH_FILE` fügt eine Datei wie eine Auswahl hinzu (nur `#if DEBUG`).
- Bilder (klein, gesichtet) `docs/screenshots/ab1-*`.

## Offen / nicht geprüft
- **Dokumentenscanner (Kamera), Fotomediathek-Auswahl, Drag & Drop, Drucken, echte Datei-Auswahl** nur gebaut, nicht bedient (Simulator/UI-Test können es nicht). Gerät (OS 27) ungeprüft.
- Mac-Ansicht nur gebaut, nicht gesehen.
- Das PDF-Aussehen mit einem echten Arbeitgeberformular ist offen (Feldnamen mit Umlauten, Schriften, Auswahllisten, digitale Signatur); PDFKit erzeugt die Erscheinung der Felder selbst, die PWA ruft `updateFieldAppearances`. Unterschiede in der Optik sind möglich.
- Serverlimit für Anhänge dem Client unbekannt (kein Endpunkt für `maxUploadBytes`); die App bricht erst nach der Antwort ab. Bei großen Scans zuerst komprimieren wäre eine Option (Fotos werden bereits verkleinert).
- Fragen: (1) Soll die Zuordnung später auch in der App bearbeitbar sein (mit Seitenvorschau und Feldliste)? (2) Soll der Urlaubsantrag auch aus der Urlaubsplanung (Vorschlag übernehmen) und dem Kalender erreichbar sein? (3) Soll „Als Anhang speichern“ den Status auf „beantragt“ setzen? Bewusst nicht: es ist keine Nutzerentscheidung dokumentiert.
