# Handoff WM2: Arbeitsmodelle, Zeitkonto-Korrektur, Statistik (iOS, iPadOS, macOS)

Branch `wm2-workmodel-stats` (von main, Build 40). Nicht gemergt, nicht gepusht, Build-Nummer unverändert, kein Upload. Vertrag 0.28.0 (Backend `contracts/openapi.yaml`, `docs/handoffs/W3-cancelled-statistics.md`). Nicht auf dem Gerät geprüft.

## 1) Arbeitsmodelle (Einstellungen › Arbeit › Arbeitsmodell; Mac: Einstellungen › Arbeit)
Spiegel des PWA-Ablaufs (`settings/work-model`). Neu:
- **Neue Version anlegen** (`POST /work-models`): Formular mit den Werten der neuesten Version vorbelegt, Start frühestens am Tag nach deren Beginn. Vor dem Speichern steht die Folge da („Die laufende Version (ab …) endet am …“) und eine Bestätigung. Rückwirkende Starts warnen (Zeitkonto kann sich ändern). Lokale Prüfung wie der Server (`NewVersionOutcome`): Start muss nach dem Beginn der neuesten Version liegen und nicht in ihren geschlossenen Zeitraum fallen, sonst `model_overlap` (Text bleibt auch bei Serverantwort erhalten). Lücken zwischen Versionen sind erlaubt.
- **Version beenden** (`PATCH /work-models/{id}`, nur `validTo`): nur für offene Versionen; Datum nicht vor dem Start und nicht auf/nach dem Start einer späteren Version (`EndVersionIssue`); Bestätigungsdialog, der sagt, dass danach kein Modell gilt.
- **Zeitstrahl**: Historie neueste zuerst mit Punkt je Version (aktuelle hervorgehoben), Lückenhinweis „Lücke vom … bis …: kein Arbeitsmodell“. „Korrigieren“ (N1b) unverändert (Warnung, Vorschau, Bestätigung).
- Felder in `WorkModelFormFields` herausgezogen und von Korrektur und neuer Version geteilt. Tages-Soll je Wochentag bleibt, wie bei der Korrektur, unverändert mitgeführt und ist nicht bearbeitbar (PWA: dasselbe Verhalten).
- Ende-Datumssemantik: **letzter Gültigkeitstag, einschließlich** (wie PWA „Letzter Gültigkeitstag“).

## 2) Zeitkonto (Einstellungen › Arbeit › Zeitkonto)
Stand (Saldo, Anfangsstand, Summe der Korrekturen, „vorläufig“), **Anfangsstand festlegen** (nur solange keiner existiert, wie PWA) und **Korrektur buchen** (Datum, Gutschrift/Abzug, h:mm, Begründung ≤ 200 Zeichen, Bestätigung). **Abweichung vom Auftrag:** Der Vertrag hat weder `GET` noch `DELETE` auf `/time/account/adjustments` (nur `POST`); „Liste und Entfernen“ sind deshalb nicht möglich. Die Seite zeigt nur die Summen und sagt vor dem Buchen, dass eine Korrektur nur mit einer Gegenbuchung ausgeglichen werden kann. Für Liste/Löschen braucht es Backend-Endpunkte (Vorschlag: `GET /time/account/adjustments`, `DELETE …/{id}` mit Revisionsspur).

## 3) Statistik (Mehr › Auswertung › Statistik; Mac-Seitenleiste „Statistik“)
`GET /time/statistics` mit Zeitraum (4 Wochen, 3 Monate, 12 Monate, dieses Jahr, seit Kontobeginn, eigener Zeitraum; höchstens 1100 Tage), Körnung Tag/Woche/Monat (Tag nur bis 93 Tage, Monat ab 28 Tagen; die Auswahl springt auf eine erlaubte Körnung) und „Mit/Ohne Rundung“ (`basis`). Kacheln (Soll bis heute, Gearbeitet, Mehr/Minder, Zeitkonto am Ende) und sechs Diagramme (Swift Charts): Zeitkonto-Verlauf (mit Anfangsstand-Basislinie), Soll und Gearbeitet, Mehr-/Minderzeit, Verteilung nach Art (Ring), Abwesenheiten (je Art), Pausen (tatsächlich/fest). Zukünftige Buckets zählen nicht in Soll/Ist-Diagrammen. Auswahl per Tippen/Ziehen mit Hinweisblase.
- **Barrierefreiheit:** jedes Diagramm hat eine Textzusammenfassung (auch sichtbar), `accessibilityChartDescriptor` (Audiografik) und eine einklappbare Werteliste („Werte als Liste“); Farbe nie allein (Legende, Namen, Werte). Hell/Dunkel über die Design-Token.
- **Layout:** adaptives Raster (iPhone eine Spalte, iPad/Mac mehrere), Seitenbreite bis 1100 pt.
- **Ältere Server:** 404 auf den Endpunkt ⇒ Erklärseite „Statistik nicht verfügbar“ (Version 0.28.0 nötig), kein Fehlerbanner; `range_too_large` und Netzfehler bleiben Fehler mit „Erneut versuchen“.

## Kern (TimetrackCore)
`TimeStatistics.swift` (Modelle, `AccountAdjustmentInput`), `StatisticsPresentation.swift` (Voreinstellungen, Körnungsregeln, `StatisticsChartData` für die Diagramme), `StatisticsStore`, `TimeAccountStore`/`AccountAdjustmentForm`, `WorkModelStore.create/end`, `WorkModel`-Erweiterungen (`checkNewVersion`, `checkEnd`, `gaps`, `endable`), `APIClient.createWorkModel/endWorkModel/createAccountAdjustment/getTimeStatistics`. UI: `Sources/Settings/{WorkModelVersionSheets,WorkModelFormFields,TimeAccountScreen}.swift`, `Sources/Statistics/*`; Strings `Sources/Settings/WM2.xcstrings` (Tabelle `WM2`), Glossar ergänzt (Arbeitsmodell-Version, Korrektur/Anfangsstand, Statistik).

## Prüfung
- Kerntests: 669 grün (`swift test --build-system native`), davon 17 neu in `WorkModelStatsTests` (Zeitstrahl-Regeln, Bestätigungs-/Fehlerpfade mit Request-Prüfung, Formular, Statistik-Dekodierung und Diagrammdaten, Körnungsregeln, älterer Server).
- Builds grün: TimetrackIOS, TimetrackMac, TimetrackWatch.
- UI-Tests `Tests/iOSUI/WorkModelStatsTests.swift` (iPhone Air, Wegwerf-Backend mit 12 Wochen Beispieldaten, Backend-`main`): `testNewVersionAndEnd`, `testTimeAccountCorrection`, `testStatisticsCharts` grün; Bilder (hell) gesichtet: Statistik oben/Mitte, Zeitstrahl, Ende-Blatt. Dunkel, iPad, große Schrift nicht fotografiert.

## Offen
- Gerät, VoiceOver-Audiografik, Mac-Oberfläche (nur gebaut, nicht gestartet).
- Zeitkonto: Liste/Löschen braucht Backend (siehe oben).
- Statistik-Diagramme nutzen nur Darstellungsdaten des Servers; Auswertung nach Lernfeld/Ort gibt es nicht.
- Tages-Soll je Wochentag nicht bearbeitbar (wie PWA und N1b).
