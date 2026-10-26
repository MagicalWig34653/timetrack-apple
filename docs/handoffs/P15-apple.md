# P15 – Rechtsprofile, Zeitkonto-Anpassungen, Prüfmarkierung (Apple-Apps)

Stand: 26.10.2026, Branch `p15-profile-adjustments` (von `main` 8d1b1be). Backend-Vertrag 0.32.0 (R2 0.29.0, ADR-0028; X3). Gilt für iOS/iPadOS/macOS; watchOS nur gebaut.

## Umgesetzt

- **Rechtsprofil je Arbeitsmodell** (Kern: `Models/LegalProfile.swift`, `WorkModel.legalProfileId`, `WorkModelInput`/`WorkModelForm.legalProfileId`, `WorkModelStore.profiles`/`loadProfiles()`): Auswahl `arbzg-adult-de` / `jarbschg-minor-de` im Editor (Korrektur und neue Version), Regelzusammenfassung und Quellen aus `GET /legal-profiles` (eingebaute Ersatzliste bei 404), Hinweis „Informative Hinweise, keine Rechtsberatung“ und der Satz, dass eine leere Hinweisliste keine Rechtskonformität bedeutet. Erklärung: Profil gilt ab `validFrom`, Wechsel (z. B. mit 18) per neuer Version, keine automatische Umstellung. Karte der Version zeigt das Profil. Servervalidierung (400 `invalid`, 409 `model_overlap`, 412 `stale_version`) mit deutschen Kontexttexten (`TimetrackError.germanMessage(in: .workModel)`).
- **Schule (Minderjährige)**: `DayEvaluation.legalProfileId/legalWarnings/schoolLessonCount`, `PUT /time/days/{date}` mit `schoolLessonCount` (explizites `null` zum Löschen, `APIClient.setSchoolLessonCount`, `TimeListStore.setSchoolLessons`). Tagesansicht (Woche, Monatsdetail, Mac-Liste): Hinweise (`legalWarnings`, deutsche Texte aller 7 Codes, neue Pausencodes `break_missing_60`, `work_over_4h30_without_break` über `BreakHint.germanText`) und Auswahl der Unterrichtsstunden (0–20, „Nicht angegeben“) an Tagen mit Schulabschnitt und Minderjährigenprofil. Die Gutschriften 8/40 h stehen als Produktannahme im Text, nicht als gesetzlicher Wert.
- **Zeitkonto-Anpassungen** (`TimeAccountStore`, `AccountAdjustment(Page)`, `APIClient.listAccountAdjustments/deleteAccountAdjustment`): Liste (neueste zuerst, Seiten zu 50, „Weitere laden“), Löschen mit Bestätigung (nennt Betrag, Datum, Saldoänderung; beim Anfangsstand zusätzlicher Hinweis), Saldo wird aus der Serverantwort übernommen, Liste und `onSaved` (Heute-Saldo) aktualisiert; 404 lädt die Liste neu und zeigt „gibt es nicht (mehr)“; 409 beim zweiten Anfangsstand erklärt; ältere Server ohne Liste (404) zeigen Hinweis statt Fehler. Texte zu „kann nicht gelöscht werden“ in WM2 korrigiert. Buchen lädt die Liste neu.
- **needsReview quittieren** (`SegmentCorrection.acknowledgeReview` sendet `needsReview:false`, `TimeListStore.acknowledge`, `ReviewStore.confirm` quittiert zusätzlich am Server und merkt lokal weiter vor für ältere Server): Marker in Listen gab es schon (Warnsymbol mit VoiceOver „Zu prüfen“, Mac-Chip); neu Knopf „Als geprüft markieren“ im Eintrags-Editor (iOS), Wischaktion „Geprüft“ und VoiceOver-Aktion in der Wochenliste, Kontextmenü und VoiceOver-Aktion im Monatsdetail, Mac: Knopf im Inspektor und Kontextmenü. Laufende Einträge lassen sich nicht quittieren (Ende fehlt). 412/400/404 mit deutschen Texten (`.reviewAcknowledge`).
- Texte in `Sources/Common/P15.xcstrings` (Tabelle „P15“), Ansichten in `Sources/Common/P15Support.swift`.

## Prüfung

- `swift test --build-system native --no-parallel` im Kernpaket: 825 Tests grün (+18 in `ProfileAdjustmentsTests`: Dekodierung Profile/Tag/Anpassungsseite, Formular-Round-Trip, Profil im Body, Fallback bei 404, Fehlerabbildung, Liste/Seiten/Löschen/404/Buchen, Quittierung mit If-Match, `schoolLessonCount` als Wert/`null`).
- Unsignierte Builds iOS (Simulator), macOS und watchOS grün.
- UI-Test `ProfileAdjustmentsTests` (iPhone-Simulator, Wegwerf-Backend mit dem lokalen Debug-Build, Stand 0.32.0): Profilwahl im Editor, Korrektur buchen, in der Liste sehen, mit Bestätigung löschen, Saldo wieder wie vorher. Bilder `docs/screenshots/p15-*.png`.

## Nicht geprüft / offen

- Quittieren (Knopf, Wischaktion, Kontextmenü, Mac-Inspektor) nur über Kerntests und Build, kein UI-Test (Wegwerf-Backend liefert keinen markierten Eintrag).
- Tagesansicht mit Hinweisen und Unterrichtsstunden ohne UI-Test und ohne Bild (kein Minderjährigen-Datensatz im Seed); VoiceOver, iPad, Mac-Fenster, große Schrift, Gerät ungeprüft.
- Speichern eines Profilwechsels gegen das Backend nicht in der UI getestet (nur Auswahl); neue Version mit Profil nur über Kerntest mit Mock.
- Fachlich offen laut ADR-0028: Gutschriften 8/40 h, Wegezeiten, Blockunterricht, Wochenendausnahmen; die UI behauptet keine Konformität.
- Kein Merge, kein Build-Hochzählen, kein TestFlight (Lead). Die Statistik (`legalWarningDays`/`breakHintDays` in Buckets) wird nicht dargestellt.
