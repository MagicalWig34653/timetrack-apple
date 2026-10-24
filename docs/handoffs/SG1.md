# SG1 – Vorschläge der Automatik und Papierkorb „Storniert“ (iPhone, iPad, Mac)

Branch `sg1-suggestions-trash` (Worktree `timetrack-apple-wt/sg1`) von `main` (Build 40). Nicht gemergt, nicht gepusht, nichts hochgeladen, Build-Nummer unverändert. Grundlage: Vertrag 0.28.0, Backend-Handoff `W3-cancelled-statistics.md`.

## 1. Vorschläge („Zu prüfen“)
- **Befund:** `GET /time/suggestions` kennt nur `start` (Ankunft am Ort im Modus „Vorschlag“) und `end` (Verlassen bei laufendem Timer, oder fehlendes Ende eines von der Automatik gestarteten Eintrags). Letzteres war schon Q1; die übrigen Vorschläge landeten bisher nur im Web.
- **Wortwahl (Glossar):** „Zu prüfen“ ist Zähler, Chip, Banner, Blatt- und Seitentitel für alles, was auf eine Entscheidung wartet; „Vorschläge“ ist nur die Abschnittsüberschrift darin, „Einträge prüfen“ der Q1-Abschnitt darunter. „Storniert“ statt Papierkorb.
- **Kern:** `SuggestionEntry`/`SuggestionEntries` (offene Vorschläge ohne die, die ein Q1-Eintrag schon trägt oder deren Eintrag erledigt ist; chronologisch), `SuggestionDraft` (Anpassen: Zeiten nie in der Zukunft, Ende nach Beginn), `ReviewStore` um `suggestions`, `accept`, `reject`, `acceptAll`, `rejectAll` (Teilerfolge, erster Fehler gemeldet) erweitert; `count` = Q1-Einträge + Vorschläge.
- **UI:** Abschnitt `SuggestionsSection` (geteilt iOS/Mac) mit Karte je Vorschlag: Tag, Zeit, Art, Grund („Du bist bei „Büro“ angekommen.“, Ortsname aus `TodayStore.places`), Aktionen „Beginn um hh:mm Uhr übernehmen“/„Ende um … übernehmen“, „Anpassen“ (Blatt; Start: Beginn, optional Ende, sonst läuft der Timer ab dem Beginn; Ende: nur Ende), „Ablehnen“. Sammelaktionen „Alle übernehmen (n)“/„Alle ablehnen“ erst nach Rückfrage; was sich nicht buchen lässt (409), bleibt stehen, Ergebnis als Zeile. **Nichts wird ohne Tipp gebucht.** Unbekannte Vorschlagsarten lassen sich nur ablehnen.
- **Einstiege:** iPhone/iPad: Chip auf Heute, Banner in Zeit, Mehr › „Prüfen und Storniert“ › „Zu prüfen“ (Zähler), Badge an den Tabs Heute, Zeit, Mehr und in der iPad-Seitenleiste; das Q1-Blatt (`ReviewSheet`) zeigt die Vorschläge oben. Mac: Seitenleistenpunkt „Zu prüfen“ (Badge) mit `SuggestionsMacScreen`; der Chip auf Heute ist dort jetzt antippbar. Q1-Einträge sind auf dem Mac: Vorschlag übernehmen, „Passt so“/„Läuft noch“, Sprung nach „Zeit“ (Anpassen/Löschen dort).
- **Benachrichtigungsaktionen:** Es gibt keine Mitteilung für Vorschläge (nur L4 „Timer stoppen?“ lokal, F2 Fokus); der Server-Push `pending_suggestions` ist in der App nicht angebunden (kein APNs). Nicht gebaut.

## 2. Storniert
- **Kern:** `CancelledSegment`/`CancelledSegmentPage`/`PurgeSummary`/`PurgeScope`, API `listCancelledSegments`, `restoreSegment` (If-Match), `purgeSegment` (`permanent=true`), `purgeCancelledSegments(scope, dryRun:)`, Fehlercodes `segment_not_cancelled`, `purge_scope_required`; `CancelledStore` (Seiten à 50, Wiederherstellen mit `RestoreFailure` overlap/timerRunning/changedElsewhere, `preview` per dryRun, `purge`).
- **UI (geteilt):** `CancelledScreen`: Karte je Eintrag (Tag, Zeit, Dauer, Art, „Storniert am …“, Grund), „Wiederherstellen“, „Endgültig löschen …“; Menü: Auswählen (Mehrfachauswahl, „Auswahl endgültig löschen (n) …“, Alle auswählen), „Alle endgültig löschen …“. Wiederherstellen-Konflikte erklärt die Karte selbst (Überschneidung/Timer läuft/inzwischen geändert). `PurgeConfirmSheet`: zählt per dryRun („1 Eintrag wird endgültig gelöscht“, Einträge, Korrekturen, Vorschläge, Timer-Ergebnisse), Warnung „unwiderruflich, keine Spur“, Wort „LÖSCHEN“ tippen (Groß/Klein egal), erst dann aktiv; bei 0 nichts zu löschen; Haptik. Nach Erfolg lädt Heute/Zeit/Zu prüfen neu.
- **Einstiege:** Mehr › Storniert; Mac-Seitenleiste „Storniert“ (⌘-Menü „Gehe zu“ nummeriert sie mit). Mehr-Spalte der Liste, Dynamic Type über die Design-Bausteine; VoiceOver: Karten als Container, im Auswahlmodus als Schalter mit Zustand.

## Tests und Prüfung
- Kerntests 678 grün (neu `SuggestionsTrashTests.swift`: Einträge/Reihenfolge/Duplikate, Draft-Regeln, Store: Zählung, Übernehmen mit/ohne Zeiten, Ablehnen, 409 bleibt, Sammelaktionen; Storniert: Dekodierung, Seiten, Wiederherstellen inkl. If-Match und 409/Reload, dryRun-Abfrage, Löschen einzeln/alle, Fehler).
- Builds unsigniert iOS, macOS, watchOS: BUILD SUCCEEDED.
- UI-Tests `Tests/iOSUI/SuggestionsTrashTests.swift` gegen Wegwerf-Backend (Seed `scripts/seed-sg1.py`: zwei Orte im Vorschlagsmodus, zwei Start-Vorschläge, drei stornierte Einträge, einer überschneidet einen lebenden): Storniert (Liste, Wiederherstellen-Konflikt, Wiederherstellen, Löschen mit Wort) bestanden; Vorschläge (Anpassen mit Ende bucht; Übernehmen scheitert mit 409 „überschneidet sich“, Vorschlag bleibt, Ablehnen bucht nichts) bestanden (iPhone-18-Pro-Simulator, ein Simulator gebootet). Bilder `docs/screenshots/sg1-*` (verkleinert) gesichtet.

## Offen / nicht geprüft
- Gerät, VoiceOver, große Schrift, iPad und Mac-Fenster nicht gesehen (Mac nur gebaut).
- Kein Vorschlagsdienst im Backend außer Ankunft/Verlassen; keine Mitteilungen/Push für Vorschläge.
- Kein Zeitraumfilter in „Storniert“ (der Vertrag kann `from`/`to`; Scope `.range` ist im Kern, UI nutzt nur Einzeln/Auswahl/Alle).
- Wiederherstellen schreibt im Server-Protokoll „Restored: Aus Storniert wiederhergestellt“ nicht; die App sendet keinen eigenen Grund (Standard des Servers).
