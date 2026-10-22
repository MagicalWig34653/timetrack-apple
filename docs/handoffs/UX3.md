# UX3 – Variante A, erste Schritte ohne Zeit-Tab/Kalender (iOS, Mac, Widgets)

Branch `ux3-variant-a` (Worktree `timetrack-apple-wt/ux3`), main mit PL1, LA4 und Z2 (Build 26) eingemergt. **Build-Nummer nicht erhöht, nichts hochgeladen, nicht gepusht.** Nur Claude. Grundlage: `docs/analysis/UX1-ui-audit.md`, `docs/concepts/UX2/README.md` (Migrationsplan Schritt 1 und 2 plus Quick Wins).

## Umgesetzt
| Punkt | Inhalt | Dateien |
| --- | --- | --- |
| Jetzt-Leiste (Schritt 1) | `tabViewBottomAccessory` über der Tab-Leiste auf allen Tabs: läuft ein Timer, tickende Uhr h:mm:ss, Art, runder roter Stopp (44 pt), Tipp links öffnet Heute; sonst Art-Menü und „Starten“. Liquid Glass vom System, bei „Transparenz reduzieren“ deckende Kapsel mit Rand, im Inline-Modus nur Symbole. VoiceOver: ein Element „Arbeit, läuft seit 1 Stunde, 2 Minuten“ (minutengenau, die tickenden Ziffern sind versteckt), Stopp/Start/Art mit Labels. iPad/Mac: Seitenleisten-Fußzeile bzw. Werkzeugleiste sind unverändert vorhanden (geprüft, nichts geändert). | `Sources/iOS/NowBar.swift`, `RootView.swift` |
| Mehr (Schritt 2) | Tab „Einstellungen“ heißt „Mehr“ (Symbol `ellipsis.circle`): Konto, „Im Web“ (Berichtsheft, Auswertung und Export, nur bei aktivem Modul, öffnen die Web-App; Berichtsheft nativ ist ein eigenes Paket), Erinnerungen (Urlaub, Überstunden), Automatik und Kalender, Zeile „Einstellungen“. Die S2-Seiten (Arbeit, Darstellung, Uhr, Info) sind unverändert in `SettingsView`; nur Erinnerungen und Automatik zogen nach Mehr um. Kennung `sidebar.more`. | `MoreView.swift`, `SettingsView.swift` |
| Heute-Karte entdoppelt | Ring ohne Prozent, „Gearbeitet 7:15“, ein Satz „Soll 7:42 · noch 0:27“ (bzw. „erreicht“, „darüber“), Zeitkonto als einzige Kachel; Info-Knopf erklärt Begriffe; „vorläufig“ per Tipp erklärt. | `Sources/Common/UX3Support.swift` (iOS und Mac) |
| Falsche Defizit-Warnung | `DayStanding`: vor dem ersten Eintrag keine Differenz, an freien Tagen kein Ring und kein „noch“; `DayDeltaPolicy` (Zukunft ausgeblendet, heute neutral, nur vergangene Tage warnen) ist getestet und **noch nicht im Zeit-Tab verdrahtet** (siehe Schnittstelle). | `DayStanding.swift` |
| Begriffe | Glossar `docs/glossary-ui.md`: Eintrag statt Zeitabschnitt/Abschnitt, Timer, Gearbeitet statt Erfasst, „noch X bis Soll“ statt Differenz; Kataloge iOS, Mac, Watch, Widget, Core-Fehlertexte angepasst. | Kataloge |
| Widget-Sekunden | „Gearbeitet“ in Home-Widgets als h:mm, Zeitleiste minütlich bei laufendem Timer; 10-pt-Hinweis auf `caption2`. | `WidgetViews.swift`, `TimetrackProvider.swift` |
| Live Activity bei Fahrt | Kein Tagesbalken, kein geplantes Ende, keine Schätzung bei Art Fahrt (`LiveActivityTarget.desired`). | `LiveActivityState.swift` |
| Sendestatus | Statuszeile unter der Navigationsleiste (iPhone, iPad, Mac), nur bei „Wird gesendet · n“ oder „Offline“, aus `TodayStore.syncStatus`. | `SyncStatusLine` |
| Abwesenheitsfarben | Urlaub smaragdgrün (war Arbeit-Blau), Sonstiges schiefergrau (war Schule-Violett). Weicht bewusst von der PWA ab (`DESIGN-NATIVE.md`). | `Tokens.swift` |
| Tab-Symbole (F02) | Heute `clock`; Zeit-Symbol bleibt `calendar` (Z2). | `TimetrackIOSApp.swift` |
| VoiceOver Uhr (F26) | Timer-Karte spricht minutengenau. | `TimerHero.swift` |
| Konzept | `docs/concepts/onboarding.md` (nicht gebaut). | |

Bewusst nicht geändert: Krank/Urlaub-Schnellaktionen bleiben auf Heute (kein anderer schneller Weg vorhanden; Nutzerentscheidung erlaubt das). Kalender, Zeit-Tab, Urlaub-Tab, Planung blieben unberührt (Z2/PL1).

## Tests und Messungen
- `swift test --build-system native`: TimetrackCore 494 Tests (+22 gegenüber dem Stand vor UX3: 472, davon 8 neue: `DayStandingTests`, `LiveActivityTravelTests`), TimetrackDesign 31 Tests; alle grün.
- Builds iOS, macOS, watchOS (unsigniert): grün, auch nach dem Merge von Z2.
- UI-Tests (iPhone-18-Pro-Simulator, Wegwerf-Backend): neu `NowBarTests` (Start/Stopp aus anderem Tab, Hit-Target ≥ 44 pt, Mehr-Inhalt, Tageskarte ohne „Differenz“ und mit Begriffserklärung) grün; `SmokeTests`, `TodayButtonsTests` grün. Bestehende Tests angepasst, nicht gelöscht: Zugang zu Einstellungen läuft über `app.openSettings()` (Mehr › Einstellungen), Automatik über `app.openMore()` (`Tests/iOSUI/MoreNavigation.swift`). **Nicht grün, ungeklärt:** `AutomationFlowTests.testSettingsPage` (Seite „Standortautomatik“ erreicht, aber der Ort „Büro Test“ mit „Direkt“-Auswahl fehlt; Wegwerf-Seed enthält vermutlich keinen Ort, kein Navigationsproblem; `testNewPlaceSheetAndGuide` scheitert ebenfalls an `automation.place.new`) und `ParityFlowTests.testParityFlow` (Navigation nach Mehr › Einstellungen funktioniert, Urlaub-Schritt läuft; scheitert danach an der Arbeitsmodell-Vorschau, Zeile 92 ff., und an `settings.about` nach dem Zurückgehen). Beide wurden **nicht gegen main ohne UX3 verglichen**; es ist offen, ob die Ursache vorher bestand (Seed/Zeitabhängigkeit) oder vom Umbau stammt. Nächster Schritt: gleichen Lauf auf `main` Build 26 wiederholen.
- Bilder: `docs/screenshots/ux3-nowbar-running.png`, `ux3-more.png`, `ux3-today-terms.png` (verkleinert, synthetische Daten).

## Schnittstelle für das Folgepaket (Planung, nach Z2/PL1)
- `AppSection` hat jetzt `today, time, vacation, more`; die Gruppe `.planning` enthält nur `vacation`. Beim Zusammenlegen zu „Planung“ genügt es, den Fall `vacation` zu ersetzen; `Mehr` bleibt vierter Tab. Der Z2-Zeit-Tab hat ein eigenes „Mehr“-Menü (Planung, Freigaben); dieses sollte dann auf den Tab „Mehr“ verweisen oder darin aufgehen, damit es nicht zwei „Mehr“ gibt. **Offene Entscheidung.**
- Freigaben (PL1) gehören in `MoreView.webRows` bzw. eine native Zeile, sobald Planung zusammengelegt ist.
- `DayDeltaPolicy.presentation(day:today:doneSeconds:targetSeconds:hasStarted:)` ersetzt in `Sources/iOS/TimeView.swift` (`DayHeader`, Zeilen mit `deltaSeconds`) und im Wochenkopf das orange „−x:xx“; Texte `ux3.standing.*` bzw. „noch X offen“ sind im Glossar vorgesehen. Z2 baut diese Dateien um, deshalb hier nicht angefasst.
- Noch nicht vereinheitlichte Wörter in Kalender/Zeit/Mac-Inspector: Tabelle am Ende von `docs/glossary-ui.md`.
- Schritt 6 des Migrationsplans (Tap- und Zeitmessung mit dem Nutzer) steht aus.

## Offen / nicht geprüft
- Jetzt-Leiste auf echtem Gerät mit OS 27: Verhalten von `tabViewBottomAccessory` bei Tastatur, großer Schrift (Accessibility-Größen) und Dark Mode nur im Simulator hell gesichtet; Verdeckung des Listenendes durch die Leiste ist im Bild sichtbar (System-Inset), Gerät ungeprüft.
- Haptik der Leiste: Start/Stopp laufen über die Store-Ergebnisse (H1), „Dezent“ bleibt Standard; Gefühl ungeprüft.
- VoiceOver-Durchlauf, Reduce-Transparency-Darstellung der Leiste nur aus Code.
- Mac-UI nur gebaut; Statuszeile und Tageskarte dort ungesehen.
- Widget-Minutenraster und Live-Activity-Fahrt: nur Unit-Tests/Build, kein Gerät.
- Fragen: (1) Sollen die Web-Zeilen unter „Im Web“ bleiben, bis das native Berichtsheft kommt? (2) Zwei „Mehr“ (Zeit-Toolbar und Tab): zusammenführen im Folgepaket?
