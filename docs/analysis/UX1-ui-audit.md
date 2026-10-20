# UX1 – UI-Audit der Apple-Apps (Analyse, kein Umbau)

Stand: 20.10.2026, Branch `ux1-ui-audit` (von `main`, Build 22). Es wurde kein App-Code geändert.

## 0. Grundlage und Grenzen (bitte zuerst lesen)

- **Belegarten.** `[S]` = Screenshot in `docs/screenshots/` (die zehn für dieses Dokument gewählten heißen `ux1-*.png`, verkleinert; Originale tragen die genannten Namen), `[C]` = Code, `[D]` = Dokument/Handoff, `[?]` = Vermutung, nicht belegt.
- **Keine neue Aufnahme-Runde.** Die Simulatoren (iPhone 18 Pro, iPad Pro 13) werden gerade von Z2/PL1 genutzt, und für frische Bilder wäre ein Wegwerf-Backend samt UI-Test-Lauf nötig gewesen. Ich habe deshalb die vorhandenen Bilder der Pakete T2, Z1, S2, V3, AD1, LA2/LA3, A7 gesichtet. Das ist eine Schwäche des Audits: Die Bilder stammen von 16.–20.10.; Heute-Tab, Zeit-Tab und Kalender werden gerade von Z2/PL1 umgebaut, Aussagen dazu können nach deren Merge veraltet sein. Ältere Bilder (`iph-*`, `watch-today`, `a7-*`) habe ich nur genutzt, wenn der Code seitdem unverändert ist.
- **Nicht gesehen:** echte Geräte, echtes Liquid-Glass-Rendering der Mac-Seitenleiste (die Mac-Aufnahme `TT_DEV_SNAPSHOT_DIR` zeigt weder Glas noch Seitenlisten-Inhalt, `[D] DESIGN-NATIVE.md` „Prüfung“), VoiceOver-Durchlauf, Dynamic Type im Kalender/Urlaub, Dark Mode auf Zeit/Kalender/Mac, macOS-Widgets, echte Dynamic Island, Smart Stack. Wo ich dazu etwas sage, ist es aus Code abgeleitet.
- **Maßstab.** Apple HIG und die genannten Vorbilder (Kalender, Erinnerungen, Fitness, Health, Things, Fantastical, Timery, Streaks). Ich bewerte die App als Zeiterfassung für den Alltag: tägliches Starten/Stoppen, gelegentliches Korrigieren, seltene Planung.

## 1. Gesamturteil (ungeschönt)

Die App ist **sauber gebaut, aber noch kein Produkt mit eigener Handschrift**. Die Designschicht (`TimetrackDesign`) ist für ein Alpha-Projekt ungewöhnlich diszipliniert: Tokens, Kontrasttests, Reduce-Transparency-Fallback, Dynamic-Type-Layoutwechsel, zentrale Haptik. Das Fundament ist stark.

Was fehlt, ist **Produktdenken über der Komponentenebene**:

1. **Alles ist gleich laut.** Jede Information liegt in einer weißen Karte gleicher Größe; Ring, Kacheln, Chips, Banner, Listenkarten haben fast gleiches Gewicht. Es gibt kein Element, das beim Öffnen „die eine Antwort“ gibt (Fitness: Ringe; Things: „Heute“-Liste; Timery: laufender Timer als feste Leiste).
2. **Das System spricht in Buchhaltersprache.** „Erfasst“, „Soll“, „Differenz“, „Zeitkonto“, „vorläufig“, „bewertet“ stehen nebeneinander, ohne dass die App sagt, was das für den Nutzer bedeutet („Du hast heute 7:15 gearbeitet, 0:27 fehlen bis Feierabend“).
3. **Die Informationsarchitektur wächst nach Funktionen, nicht nach Aufgaben.** Fünf Tabs (Heute, Zeit, Kalender, Urlaub, Einstellungen), dazu Planung in drei Orten (Zeit/Woche, Kalender, Urlaub-Tab), Einstellungen mit 13+ Unterseiten. Der Nutzer muss das Datenmodell des Backends verstehen.
4. **Die Plattformen wirken wie drei verwandte Apps**, nicht wie eine: Watch-App benutzt Standardblau, eigene Schriftgrößen und keine Designschicht-Komponenten (außer Chips/Glyphen); Widgets haben harte Schriftgrößen; Mac teilt Karten-Layouts mit dem iPhone statt Mac-Idiomen (Tabelle, Inspector gibt es nur in „Zeit“).

Einordnung gegenüber Vorbildern: Funktional liegt die App über Timery/Toggl (Soll/Ist, Urlaub, Standortautomatik, Fokus-Filter), visuell und im „Gefühl“ aber hinter Things/Fantastical/Streaks. Das ist keine Geschmacksfrage, sondern lässt sich an konkreten Punkten festmachen (Abschnitt 3).

## 2. Inventar der Bildschirme (Struktur laut Code)

| Plattform | Struktur | Beleg |
| --- | --- | --- |
| iPhone | `TabView` mit 5 Tabs Heute / Zeit / Kalender / Urlaub / Einstellungen (Module können Tabs ausblenden); jeder Tab eigener `NavigationStack` | `[C] Sources/iOS/RootView.swift` `MainView`, `AppSection` in `TimetrackIOSApp.swift:125` |
| iPad | `NavigationSplitView`, Seitenleiste gruppiert (Erfassen / Planung / App), Fußzeile mit Konto + laufender Uhr | `[C] RootView.swift`, `[S] ux1-ipad-time.png` |
| Mac | `NavigationSplitView` mit Seitenleiste (nur Erfassen/Planung; Einstellungen als eigenes Fenster), Timer-Knopf in der Werkzeugleiste, Menüleisten-Extra, Befehle (⌘N, ⌘1–4) | `[C] Sources/Mac/RootView.swift`, `MacCommands.swift`, `[D] AD1.md` |
| Watch | Ein `NavigationStack`: Timer, Statuszeile, Summe, Abschnitte; Einstellungen per Zahnrad; Komplikationen; Smart-Stack-Live-Activity | `[C] Sources/Watch/MainView.swift` |
| Widgets | Home small/medium/large, Sperrbildschirm circular/rectangular/inline, Steuerzentrale-Schalter, Live Activity + Dynamic Island, macOS-Widgets | `[C] Sources/WidgetShared/*`, `[S] ux1-widgets.png`, `ux1-liveactivity.png`, `ux1-watch-la.png` |

Zahlen aus dem Code (Sources + Design-Paket): 48 `accessibilityLabel`, 3 `accessibilityHint`, 4 `accessibilityValue`; 4 Stellen mit Reduce-Motion-Prüfung, 5 mit Reduce-Transparency; **0** Verwendungen von `accessibilityDifferentiateWithoutColor`; 24 feste `font(.system(size:))`, 61 feste `frame(width/height: Zahl)`; 1× `swipeActions`, 3× `contextMenu`, 1× `searchable`; **0** `ContentUnavailableView` (eigenes `EmptyState` 19×); 659 Texte iOS, 426 Mac, 36 Watch im Katalog; **kein Onboarding** (Suche nach „onboarding“ ohne Treffer in `Sources`).

## 3. Befunde

Schweregrad: **H** = schadet täglicher Nutzung oder Vertrauen, **M** = spürbare Schwäche, **N** = Feinschliff. Aufwand: S (≤ 1 Tag), M (2–4 Tage), L (> 1 Woche oder Konzeptentscheidung).

### 3.1 Informationsarchitektur und Navigation

**F01 (H, M) – Planung liegt an drei Orten, Kalender/Zeit/Urlaub überlappen.**
Beleg `[S] ux1-iph-time.png`, `ux1-iph-calendar.png`, `ux1-iph-vacation.png`, `ux1-ipad-time.png` (zeigt noch die Segmente Liste/Woche/Planen); `[D] Z1.md`, `V3.md`, `N1a.md`. Z1 hat die Segmente im Zeit-Tab schon entfernt – gut. Es bleiben: Kalender (Tag planen, Abwesenheit, Zeitabschnitt), Urlaub-Tab (Konto, Liste, „Urlaub planen“, Erinnerungen), Einstellungen (Urlaubsanspruch, Urlaubserinnerungen). Apple Kalender/Fantastical haben **einen** Zeitraum-Ort, Abwesenheiten sind dort Ereignisse. Empfehlung: Urlaub als Unterseite/Filter des Kalenders („Abwesenheiten“) plus Urlaubskonto als Karte im Kalender- oder Heute-Kontext; Tab-Zahl auf 4 senken (Heute, Zeit, Kalender, Einstellungen oder „Mehr“). Das ist eine Produktentscheidung (siehe 6, Frage 1).

**F02 (M, S) – Tab-Symbole und -Namen unterscheiden sich schlecht.**
`[C] TimetrackIOSApp.swift:150-158`: „Heute“ = `sun.max`, „Zeit“ = `calendar.day.timeline.left`, „Kalender“ = `calendar`. Zwei kalenderartige Symbole, „Heute“ als Sonne kann „Wetter/Helligkeit“ lesen (`[S] ux1-iph-time.png`, Tabbar unten). Reminders/Fitness verwenden Symbole, die den Inhalt benennen: Heute = `timer` oder `clock`, Zeit = `list.bullet.rectangle`/`clock.arrow.circlepath`, Kalender = `calendar`. Quick Win.

**F03 (M, M) – Einstellungen sind eine 13+-Seiten-Baumstruktur mit Technik an erster Stelle der Benennung.**
`[S] ux1-iph-settings.png`: Konto, Darstellung, Arbeit (Arbeitsmodell, Urlaubsanspruch, Urlaubserinnerungen), Automatik und Kalender (Kalender, Standortautomatik, Fokus-Filter), Apple Watch, … weitere Gruppen darunter (Server, Module, Über). S2 hat bereits entrümpelt; offen: „Urlaubsanspruch“ und „Urlaubserinnerungen“ liegen in „Arbeit“, aber im Urlaub-Tab gibt es das Regler-Symbol für dieselben Werte (`[D] R3.md`: „Anspruch nur noch im Einstellungsmenü oben rechts“ **und** laut S2 in Einstellungen) – zwei Wege zum selben Wert. Empfehlung: einen Weg behalten (am Ort der Nutzung, im Urlaub-Tab), in Einstellungen entfernen.

**F04 (M, S) – Nutzerbegriffe schwanken: „Zeitabschnitt“, „Eintrag“, „Segment“.**
`[S] ux1-iph-today.png` („Kein Zeitabschnitt läuft“), `ux1-iph-time.png` („Keine Einträge“), Kalender-Aktion „Zeitabschnitt“, Strings `today.no_segments` = „Noch keine Einträge heute.“ mit Kopf „Zeitabschnitte heute“ (`[C] Localizable.xcstrings iOS`). Ein Wort wählen (Vorschlag: „Eintrag“ oder „Zeitraum“; „Zeitabschnitt“ ist Backend-Vokabular).

### 3.2 Heute-Bildschirm (Primärweg)

**F05 (H, M) – Heute zeigt auf Nicht-Arbeitstagen Nonsens-Zahlen und leeren Ring.**
Beleg `[S] ux1-iph-today.png` (Sonntag): Ring mit „–“ (kein Soll), „Erfasst 7:15 von 0:00 Soll“ (die Zahl 7:15 stammt von Montag-Daten der Wegwerf-Seeds, das Muster bleibt), Differenz „+7:15“ in Grün, Chip „vorläufig“. Code `[C] Sources/iOS/TodayView.swift:108-118`: bei `target == 0` wird der Ring leer mit „–“ gezeichnet. Eine Profi-App zeigt an freien Tagen keinen Zielring, sondern „Heute frei“ / „Feiertag“ / „Urlaub“ als Tageskarte, und die Differenz nur, wenn es ein Soll gibt. Mac `[S] ux1-mac-today.png`: „0 %“-Ring bei Soll 7:42 und „Differenz −7:42“ in Orange schon am Morgen vor dem ersten Eintrag – die App meldet am Dienstagmorgen „Defizit“, bevor der Tag begonnen hat. Empfehlung: Differenz erst nach Tagesbeginn (erster Eintrag) oder nach geplantem Ende als „fehlt“ formulieren; Ring nur bei Soll > 0.

**F06 (M, S) – Aufbau der Heute-Karte: Hauptaktion ist gut, aber ihr Zustand ist zu leise.**
`[S] ux1-iph-today.png`: Starten ist der einzige, deutlich gefüllte Knopf – richtig (HIG, eine Hauptaktion). Aber: (a) Die Art-Auswahl (Arbeit/Fahrt/Schule) sitzt zwischen Text und Start, drei Elemente zum Starten; „Timer starten in ≤ 1 Tap“ gilt nur, weil `lastKind` gemerkt wird (`[C] TodayView.swift` `@AppStorage("ios.lastKind")`) – korrekt, aber der Nutzer sieht nicht, dass die letzte Art vorausgewählt ist, und kann die Wahl nur über erneutes Tippen ändern. (b) Idle-Zustand: Icon + zwei Textzeilen („Kein Zeitabschnitt läuft“ / „Wähle eine Art und starte den Timer.“) verbrauchen ~30 % der Kartenhöhe für eine Aussage ohne Information. Timery/Toggl zeigt hier „Start“ + letzte Beschreibung; Streaks zeigt Zustand statt Aufforderung. Empfehlung: Idle-Text auf eine Zeile oder weglassen, Start-Knopf trägt die Art („Arbeit starten“, Art per Langdruck/Menü wechseln), Hilfszeile nur im Leerzustand beim ersten Start.

**F07 (M, M) – Redundanz: derselbe Tagesstand steht dreimal.**
`[S] ux1-iph-today.png`, `iph-dark-today-running.png`: Ring (Prozent) + große Zahl „Erfasst 7:16“ + Kachel „Differenz −0:25“ + Zeitabschnitte-Liste (Summe pro Abschnitt) – Prozent, Erfasst und Differenz sind drei Darstellungen einer Größe. `[C] TodayView.swift` `DayStats`. Fitness-Ringe zeigen Fortschritt **oder** Zahl; Health fasst in einer Zeile zusammen. Empfehlung: Eine Kartenzeile „7:16 von 7:42 · 0:26 bis Feierabend“ mit Ring als Grafik; „Zeitkonto“ in eine Zeile darunter oder in Zeit-Tab. (A6 hatte „vorläufig“ noch dreifach, inzwischen zu einem Chip konsolidiert – gut, `[C] TodayView.swift:123`.)

**F08 (M, S) – Quick-Aktionen (Krank/Urlaub/…) stehen unter der Falz zwischen Statistik und Abschnitten.**
`[S] ux1-iph-today.png` unten: „Krank melden / Urlaub eintragen / ⋯“ als Pillen in eigener Karte. Dauerhaft sichtbare Seltenfunktion auf dem wichtigsten Bildschirm; Krank melden ist selten, wichtig, aber morgens. Besser: Überlaufmenü am Kartenrand der Tagesansicht oder Kontextaktion bei laufendem Tag ausblenden. Aufwand S, aber Produktentscheidung (Frage 2).

**F09 (M, S) – Laufender Timer: Zahl gut, Mikroaufmerksamkeit fehlt.**
`[S] iph-dark-today-running.png` (älter, Code unverändert): große tabellarische Uhr, Live-Punkt, rote „Stoppen“. Gut. Fehlt: Laufender Zustand außerhalb der App ist nur über Live Activity sichtbar (iPhone ohne Live Activity: kein Sperrbildschirm-Hinweis); in der App kein Hinweis auf die Tabs „Zeit/Kalender“, dass ein Timer läuft (Toggl/Timery: schwebende Leiste „mini player“ über der Tab-Leiste). `[C] RootView.swift`: nur auf iPad in der Seitenleisten-Fußzeile, **nicht auf dem iPhone**. Empfehlung: Mini-Leiste über der Tab-Leiste (iOS 26+ `tabViewBottomAccessory`) mit Uhr + Stopp, auf allen Tabs. Das ist der größte Alltags-Hebel im Navigationsmodell (siehe Top 10).

### 3.3 Zeit-Tab

**F10 (H, S) – Zukünftige und freie Tage zeigen rote/orange „−7:42“.**
`[S] ux1-iph-time.png`: Di 20., Mi 21. mit „0:00 von 7:42 −7:42“ in Orange. `[C] Sources/iOS/TimeView.swift:186-192` zeigt `deltaSeconds` immer, wenn ≠ 0, in Warnfarbe (`TT.warning`). Der Wochenkopf zeigt „−31:15“ als orangen Chip – ab Montag früh ein dauerhaftes „Warnsignal“. Wer sich nicht verspätet hat, bekommt ein Warnzeichen für die Zukunft. Things/Kalender zeigen keine Defizite für Zukunft. Empfehlung: Delta nur für vergangene Tage und den heutigen Tag nach dem geplanten Ende; Zukunft: nur „Soll 7:42“ in neutral; Woche: „noch 31:15 offen“ statt Minus-Chip.

**F11 (M, S) – Leere Tage als volle Karte „Keine Einträge“ wiederholt.**
`[S] ux1-iph-time.png`, `ux1-ipad-time.png`: bis zu sieben Tage, fünf davon je eigene weiße Karte „Keine Einträge“ + Plus-Knopf. Apple Kalender zeigt leere Tage als Zeile; Erinnerungen blendet leere Gruppen aus. Empfehlung: Leere Tage zu einer Zeile ohne Karte verdichten, Plus ist die Zeile selbst (Tipp). Spart rund die Hälfte der Scrollhöhe der Woche.

**F12 (M, M) – Wochenübersicht rechts auf dem iPad dupliziert die Liste.**
`[S] ux1-ipad-time.png`: rechts „Wochenübersicht“ mit Balken pro Tag und Summen, links dieselben Summen je Tag in den Kopfzeilen. Auf iPad/Mac wäre die Fläche für etwas Neues da (Verteilung nach Art, Zeitkonto-Verlauf, Planvergleich). Auf dem iPhone entfällt die Karte; dort sitzt der Verlauf unter „Wochendetails“.

**F13 (N, S) – Wochenkarte: Drill-down „Wochendetails: Zeitkonto, Plan, Durchschnitt“ ist Fließtext statt Sprungziel.**
`[S] ux1-iph-time.png`: Chevron gibt Hinweis, Text beschreibt Inhalt statt Nutzen. Neutral formulieren („Wochenübersicht“), Beschreibung als Untertitel.

### 3.4 Kalender

**F14 (M, S) – Doppelte Legende und abgeschnittene Beschriftungen.**
`[S] ux1-iph-calendar.png`: Sechs Aktionschips („Urlaub, Krank, Freigest…, Sonstiges, Eigener…, Zeitabschnitt“) **und** darunter eine Legende derselben Arten, ebenfalls mit „Freigest…“. Die Kürzung ist ein harter Mangel („Freigest…“ ist nicht lesbar; `lineLimit`/`minimumScaleFactor`-Folge). Die Chips sind Aktionen, die Legende erklärt Farben; beides gleichzeitig verdoppelt Inhalt und belegt ~25 % des Bildschirms unter dem Raster. Empfehlung: Aktionen in „+“-Menü (liegt schon oben rechts), Legende nur als Info-Taste (Apple Kalender hat gar keine), Rest für Tagesdetail (Termine, Soll, Ist).

**F15 (M, S) – Tagesdetail beginnt mit „Nicht geplant – Planung festlegen“ und dem Leerraum danach.**
`[S] ux1-iph-calendar.png`: Das Detail zum gewählten Tag zeigt „Soll 7:42, bewertet 7:15“ (Fachsprache „bewertet“), „Nicht geplant“, und die Zeitabschnitte des Tages fehlen im Bild, obwohl Montag Einträge hat (siehe Zeit-Tab). Der Kalender ist für Planung gebaut, zeigt aber keine Ist-Daten des Tages. Fantastical/Apple: Tippen auf Tag → Liste der Ereignisse. Empfehlung: Ist-Abschnitte im Tagesdetail (Z2/PL1 arbeiten genau daran – nicht doppelt bearbeiten).

**F16 (N, S) – Feiertagsfarbe Orange und „sickness“-Rosa nur Punkt.**
`[S] ux1-iph-calendar.png`: 3. und 31. Okt. orange mit Punkt, 29./30. rosa Punkte. Information nicht nur über Farbe: Legende hilft, VoiceOver-Labels vorhanden (`[D] DESIGN-NATIVE.md` A10). Kontrast Orange auf Hellgrau ~4:1 `[?]` (nicht gemessen).

### 3.5 Urlaub

**F17 (M, S) – Warnbanner bei Erstnutzung klingt nach Fehler.**
`[S] ux1-iph-vacation.png`: „Deine Urlaubseinstellungen sind noch nicht gespeichert. Angezeigt werden Standardwerte; sie gelten erst nach dem Speichern.“ – bernsteinfarbenes Info-Symbol, kein Knopf zum Speichern, der Banner steht vor dem Ring und verschiebt den Inhalt. Das ist ein **Leerzustand mit Aufforderung**, kein Warnzustand. Empfehlung: Karte „Urlaubsanspruch festlegen“ mit Knopf (öffnet Einstellungsblatt), neutral gestaltet.

**F18 (M, S) – Drei Wörter für Urlaubsstand.**
`[S] ux1-iph-vacation.png`: „Verfügbar 22 Tage“, „Nach Planung: 12 Tage“, Legende „Noch frei 12 Tage“. „Nach Planung“ und „Noch frei“ sind dieselbe Zahl in unterschiedlichen Wörtern direkt untereinander. Empfehlung: Eine Zahl groß („12 Tage frei“), Untertitel „22 verfügbar, 10 geplant“.

**F19 (N, S) – Ring-Schraffur für „geplant“ ist gut gedacht, in kleiner Größe optisch unruhig** (orange Strichelung). `[S] ux1-iph-vacation.png`. Am Gerät prüfen.

### 3.6 Komponenten und Konsistenz

**F20 (M, M) – Zwei Kartenstile plus Glas ohne klare Regel.**
`[D] DESIGN-NATIVE.md` Regel 1: Glas nur für Rahmen und Hero. In den Bildern: Heute-Timerkarte Glas mit Verlauf, alle anderen Karten flach weiß, Kalenderkopf-Buttons Glas, Tabbar Glas. Das ist stimmig im Prinzip, aber Karten haben in jeder Ansicht leicht unterschiedlichen Radius/Schatten (Karte 22 pt, Kachel, ListCard, Chips, Pillen für Aktionen, Kapseln für Art-Auswahl). Es gibt **drei Chip-Formen** (Kapsel mit Rahmen = Art-Auswahl, gefüllte Pille = Quick-Aktionen/Kalender, Status-Chip), die sich nur durch Kontext unterscheiden lassen. Empfehlung: Komponentenkatalog mit „Aktion / Auswahl / Status“ je eine Form.

**F21 (M, S) – Farbe pro Art ist dreimal belegt.**
Arbeit = Himmelblau, Fahrt = Bernstein, Schule = Violett (`[D]`), Urlaub = Himmelblau (wie Arbeit!), Sonstiges = Violett (wie Schule!). `[D] DESIGN-NATIVE.md` Tokens: `kindVacation` (sky) = `kindWork` (sky), `kindOther` (violet) = `kindSchool` (violet). Das ist PWA-Parität, aber im Kalender/Zeit-Tab ergeben sich verwechselbare Farben. Empfehlung: Abwesenheiten bekommen eigene Farbfamilie (Grün/Rosa/Teal) oder ein Symbol statt Farbe.

**F22 (N, S) – Datumszeile in Versalien mit Sperrung („FREITAG, 16. OKTOBER“).**
`[S] iph-ax-today-idle.png`: bei großer Schrift Umbruch in zwei Zeilen, wirkt schwer. Auf `ux1-iph-today.png` gut. Dynamic Type: Eyebrow auf Sentence Case umstellen oder `lineLimit(1)` + Verkürzung.

**F23 (M, S) – Typografie: 24 feste Schriftgrößen im Code, davon die meisten in Widgets/Watch.**
`[C] grep font(.system(size:`: z. B. Watch-Timer 36 pt (`Sources/Watch/MainView.swift`), Widget 34/32 pt, Zugangs-Widgets 13/14 pt, `.system(size: 10)` für „Aktualisiert um“ (`WidgetViews.swift:92`). Systemgrößen in Widgets skalieren nicht mit Dynamic Type; 10 pt sind unter dem Leseminimum. Empfehlung: `@ScaledMetric`/Text-Styles, Mindestgröße 11 pt.

### 3.7 Zustände (leer, laden, Fehler, offline)

**F24 (M, M) – Zustände sind vorhanden, aber ungleich ausgeprägt.**
`[C]`: `EmptyState` 19×, `ErrorBanner` 37×, `Skeleton` 20× – gute Abdeckung. Aber (a) Heute zeigt beim Laden Skeleton, Zeit/Kalender zeigen teils leere Karte (`[?]` nicht für jeden Bildschirm geprüft); (b) Fehler erscheinen als Banner oben im Scroll, nicht als Zustandsleiste; (c) **Offline-Zustand auf iPhone**: Statuszeile „offline/sendet N“ existiert nur auf der Watch (`[C] Sources/Watch/MainView.swift` `StatusLine`), auf iPhone/iPad/Mac keine dauerhafte Offline-/Wartend-Anzeige (Offline-Warteschlange gibt es laut `[D] STATUS.md`/LA1 für Live-Activity-Intents). Wenn jemand im Zug stoppt, sieht er nicht, ob der Stopp angekommen ist. Empfehlung: kleine, immer gleiche Statuszeile unter dem Titel („Wird gesendet · 2“ / „Offline“). Das ist ein Vertrauensthema und gehört in die Top 10.

**F25 (N, S) – `ContentUnavailableView` fehlt, eigenes `EmptyState` bildet es nach.** `[C]` 0 Treffer. Vorteil Systemkomponente: automatische VoiceOver-Semantik, Suchzustand, Updates. Aufwand S, niedriger Hebel.

### 3.8 Barrierefreiheit

**F26 (M, S) – Laufende Uhr hat feste Beschriftung mit jeder Sekunde.**
`[C] TimerHero.swift`: `Text(clock).accessibilityLabel(Text(verbatim: clock))` in `TimelineView(.periodic(by: 1))`. VoiceOver kann bei jedem Tick neu vorlesen, wenn der Fokus auf der Uhr liegt; das Label ist reiner Text ohne „läuft seit“. Besser: `accessibilityLabel("Läuft seit 1 Stunde 2 Minuten")` minutengenau, `.updatesFrequently` nur wenn nötig. `[?]` nicht mit VoiceOver geprüft.

**F27 (M, S) – Differenzierung ohne Farbe fehlt.**
`[C]` 0 Treffer für `accessibilityDifferentiateWithoutColor`. Positive/negative Differenz unterscheiden sich durch Vorzeichen (gut), Kalender-Abwesenheiten durch Legende/Label (gut); Statuschips tragen Text (gut). Offen: Art-Auswahl auf Heute unterscheidet gewählt/nicht gewählt über Füllung **und** `isSelected`-Trait (gut), aber nur Farbe/Rahmen für Sehende. Ein Haken im gewählten Chip wäre günstig.

**F28 (M, M) – Dynamic Type: bei AX-Größen frisst die Timerkarte den Bildschirm.**
`[S] iph-ax-today-idle.png` (16.10.; T2 hat Knöpfe seitdem repariert, `[S] t2-after-iph18-ax1-light-today-top.png`): Karte füllt mehr als eine Bildschirmhöhe, Start-Knopf liegt hinter der Tabbar. Die Tabbar selbst bleibt klein – bei AX-Größen sollten Tab-Beschriftungen wechseln. Empfehlung: bei `isAccessibilitySize` Idle-Text weglassen und Art-Auswahl als Menü statt drei Zeilen.

**F29 (N, S) – Wenige Hints (3).** Aktionen wie „Pause/Stopp“ in Live Activity, Plus-Knöpfe pro Tag („Eintrag für Mi 21. Okt. hinzufügen“ – `[?]` Label prüfen) brauchen Zielbeschriftung statt nur „Plus“.

### 3.9 Haptik, Animation, Mikrointeraktion

**F30 (N, S) – Haptik-Konzept ist gut, aber ungeprüft.** `[D] H1.md`: Bedeutungen statt Mechanik, 80-ms-Drossel, zentral. 32 Aufrufe. Offen: auf dem Gerät nie gefühlt (`[D] STATUS.md`). Streaks/Fitness haben „Erfolgs“-Momente beim Abschluss des Tagesziels; hier gibt es nur Start/Stopp. Nice-to-have: Tagesziel erreicht → einmalige Animation/Haptik („Soll erreicht“).

**F31 (M, M) – Animationen: 12 Stellen, kaum Übergänge zwischen Zuständen.**
`[C]`: `.animation(.smooth, value: running.id)` auf Heute, `contentTransition(.numericText())` für Uhr. Fehlt: Übergang Start→Laufend mit Matched Geometry (Karte verändert Höhe/Tönung hart), Einfügen/Entfernen von Zeilen, Zahlenwechsel in Kacheln (kein `numericText`), kein Konfetti/„Haken“ nach Speichern. Things/Fantastical leben von diesen Übergängen. Aufwand M, Gefühl-Hebel hoch, Funktionshebel gering.

### 3.10 Liquid Glass

**F32 (M, S) – Glas auf weißen Karten wird nicht sichtbar; auf Inhalt hinter der Tabbar wirkt es unruhig.**
`[S] ux1-iph-time.png`, `ux1-iph-settings.png`: Hinter der schwebenden Tabbar scheinen verschwommene Textreste durch („0:00 von 7:42“ in der Tabbar-Kante) – das ist Systemverhalten von iOS 26+/27, aber verstärkt, weil Karten **opak weiß** sind und der Inhalt hinter der Leiste harte Kontraste hat. Lösung im System: `scrollEdgeEffectStyle(.soft)` und ausreichend unterer Scroll-Inset; im Code `[?]` nicht gesetzt (nur gesucht per Stichprobe, nicht vollständig geprüft). Außerdem: Die Hintergrund-„Akzentlichter“ (`TTBackdrop`) sind das einzige dekorative Element und geben dem Glas (laut Doku) „etwas zum Brechen“ – im Screenshot fast unsichtbar.

**F33 (N, S) – Live-Activity-Glas verworfen, Watch-Knöpfe ohne Glas.** `[D] LA2.md`/`LA3.md`: deckende Füllungen (bewusst, wegen Rendering-Fehler). Konsistent mit dem Rest der App, aber optisch eine andere Sprache (satte Vollfarbknöpfe) als die Karte (`[S] ux1-liveactivity.png`).

### 3.11 Onboarding und Erstnutzung

**F34 (H, M) – Es gibt kein Onboarding.**
`[C]` kein Treffer. Erststart: Anmeldung (Passkey/Server eintragen, `[S] signin-light.png`), dann Heute mit Leerzustand. Das Backend braucht Einladung/Token, Arbeitsmodell, Urlaubsanspruch – die App setzt die Zahlen stumm auf Standard (siehe F17). Profi-Apps: 3 Schritte (Arbeitsmodell wählen, Benachrichtigungen/Standort erklären, erste Zeit starten). Gerade Berechtigungen (Standort „Immer“, Mitteilungen, Kalender) werden nur in den Einstellungen erklärt. Ohne Onboarding ist das Alleinstellungsmerkmal (Automatik) für neue Nutzer unsichtbar.

**F35 (M, S) – Serveradresse ist Teil der Anmeldung.** `[C] SignInView.swift`, `[S] signin-light.png`: „Server“-Feld in der Anmeldekarte – für Selbstbetreiber richtig, für App-Store-Nutzer irritierend. Standardserver vorbelegen, „Eigener Server“ als stille Textaktion (Regel 3 in DESIGN-NATIVE sagt das ohnehin, Umsetzung `[?]` prüfen).

### 3.12 Texte und Tonalität

**F36 (M, S) – Fachbegriffe ohne Erklärung: „vorläufig“, „bewertet“, „Zeitkonto“, „Differenz“, „Soll“.**
`[S] ux1-iph-today.png`, `ux1-iph-calendar.png`. „vorläufig“ (Tag nicht abgeschlossen) wird als grauer Chip an Ring und Wochentagen gezeigt, ohne Erklärung per Tipp. Empfehlung: Erklärung per Tipp (Popover), Wörter vereinheitlichen („Ist/Soll“ oder „Gearbeitet/Soll“).

**F37 (N, S) – Mischung aus Du-Ansprache und Systemsprache.** Starke Sätze („Sobald du den Timer startest, erscheinen deine Abschnitte hier.“) neben „Der Server nennt keine Versionsangaben (ältere Version oder nicht erreichbar)“ (`about.unavailable`), „Beim Serverwechsel wirst du abgemeldet.“ Ton: freundlich, aber Technik leakt. Für Selbsthoster okay, für App-Store-Version Zweitklassigkeit.

### 3.13 Widgets, Live Activity, Watch

**F38 (M, M) – Widgets: Sekunden im Statistik-Block, Doppelungen, keine Konfiguration.**
`[S] ux1-widgets.png`: Medium/Large zeigen „Erfasst 4:27:07“ **mit Sekunden** neben der laufenden Uhr „1:02:07“ – zwei tickende Zahlen im selben Widget, Verstoß gegen die eigene Regel „Dauern immer h:mm“ (`[D] DESIGN-NATIVE.md`). Large: große Leerfläche unter den Abschnitten. `StaticConfiguration` ohne Optionen (`[C] TimetrackWidgetIOS.swift:12`), keine Auswahl der Art zum Start, kein `widgetRenderingMode`-Umgang (kein Treffer) → im getönten iOS-Modus unvorhersehbar. Feste Hintergrundfarbe `TT.background` (`WidgetViews.swift:165`).

**F39 (M, S) – Live Activity: gute Informationsdichte, drei Varianten mit drei Layouts.**
`[S] ux1-liveactivity.png`: Sperrbildschirm (Symbol, Uhr, runde Knöpfe), Dynamic Island expanded (Uhr rechts, Knöpfe als Kapseln mit Text), Smart Stack (Zeile mit Knöpfen daneben). Alle drei zeigen **Beginn 14:05 / Feierabend 23:06** – ein Fortschrittsbalken von Beginn bis Plan-Ende **auch bei Art „Fahrt“** (Fortschritt der Arbeitszeit im Fahrtmodus?). `[D] LA2.md`: Balken = erster Beginn des Tages bis geplantes Ende. Ein Fahrt-Timer, der den Arbeitstag-Balken zeigt, ist inkonsistent mit Titel „Fahrt • Läuft“. Außerdem **Wahrnehmung**: Die Uhr zeigt die Dauer des aktuellen Abschnitts, der Balken den Tag – zwei Zeitbegriffe in einer Zeile. Alles am Gerät unverifiziert (`[D] STATUS.md`: Live Activity „nur Galerie gesichtet“).

**F40 (M, M) – Watch: eigener Stil, ohne Konto-Akzent, ohne Fehlerpfad bei fehlender Anmeldung.**
`[C] Sources/Watch/MainView.swift:130`: Start-Knopf fest `TT.defaultAccentHex`; `[D] STATUS.md` bestätigt „Watch-App selbst nutzt Standardblau“. Schriftgrößen fest (36 pt Uhr, `.footnote` Rest), keine Dynamic-Type-Abstufung; Segmentliste mit Doppeltext. Art-Auswahl als `navigationLink`-Picker: Start in einem Tipp mit gemerkter Art (gut), aber Artwechsel = zwei Tipps + Zurück. Komplikation: Akzent aus Konto (gut). Digital Crown wird nicht genutzt; kein `containerBackground`-Farbverlauf nach Art (Fitness-App färbt die ganze Ansicht nach Aktivität). Anmeldung nur über iPhone-Handoff (kein Passkey auf watchOS).

### 3.14 Mac und iPad

**F41 (M, M) – Mac: iPhone-Layout in breiterem Fenster.**
`[S] ux1-mac-today.png`: Heute-Spalte mit Timer links, Abschnitte rechts, große Leerfläche unten; Ring/Kachel/Pillen-Karten wie auf dem iPhone, Art-Auswahl als drei Kapseln (Mac-Idiom: Segmented Control/Picker). Positiv: Timer in der Werkzeugleiste, Menüleisten-Extra, Kürzel (`[D] AD1.md`). Offen: Seitenleisten-Rendering in der Aufnahme nicht sichtbar (Fenster leer links), Zeit-Liste mit Mehrfachauswahl nur dort. Kalender/Urlaub ohne Mac-Spezifika (Drag zum Ändern, Kontextmenü, Tastatur im Kalenderraster `[?]`).

**F42 (N, S) – iPad: gleiche Karten, viel Rand.** `[S] ux1-ipad-time.png`: Liste und Wochenkarte in ca. 60 % der Breite, links Seitenleiste breit mit großem Leerraum (Fußzeile unten); Statusleiste oben mit „Timetrack“ als Fensterzeile (iPadOS-Fensterleiste) und Datum. Gut für Multitasking-Fenster (`ViewThatFits`), aber keine iPad-spezifische Mehrwert-Ansicht (Woche als Raster, Drag & Drop von Abschnitten).

### 3.15 Performance-Wahrnehmung

**F43 (N, S) – Heute beim Start: Skeleton, dann Inhalt; Cache-first nur auf der Watch.** `[D] A12.md`: Watch zeigt Snapshot zuerst (342–437 ms). Auf iPhone lädt `TodayContent` beim Erscheinen und `scenePhase == .active` per `store.load()` (`[C] TodayView.swift`), kein persistierter letzter Stand beim Kaltstart (`[?]` nicht geprüft; `TodayView` zeigt `SkeletonList`, solange `model.today == nil`). Things/Kalender zeigen sofort den letzten Stand. Messen vor Entscheiden.

## 4. Top 10 (größter Hebel zuerst)

| # | Befund | Warum | Aufwand |
| --- | --- | --- | --- |
| 1 | **F09** Mini-Leiste „Timer läuft“ über der Tabbar auf allen Tabs (iPhone) | Stoppen aus jedem Tab in einem Tipp; Orientierung, ob etwas läuft; Standard bei Timery/Toggl | M |
| 2 | **F10 + F05** Keine Warnfarbe/Defizit für Zukunft und für den Tagesbeginn; Freie Tage ohne Nullring | Beseitigt falsche Alarmzustände auf dem meistgesehenen Bildschirm; stärkt Vertrauen | S |
| 3 | **F34** Onboarding in 3 Schritten + Standardserver | Erstnutzung, Berechtigungen, Arbeitsmodell; ohne das ist die Automatik unsichtbar | M |
| 4 | **F24** Dauerhafte Sync-/Offline-Statuszeile (iPhone/iPad/Mac) | Vertrauen in Erfassung unterwegs | M |
| 5 | **F07** Heute-Karte konsolidieren: eine Zeile „7:16 von 7:42 · bis Feierabend 0:26“ | Entfernt Dreifachinformation, schafft Platz für die Abschnittsliste | M |
| 6 | **F01** Navigationsmodell: Urlaub in Kalender integrieren, Tab-Anzahl senken, Planung an einem Ort | Reduziert Konzeptlast, deckt sich mit Z1/PL1-Richtung | L (Konzeptentscheidung) |
| 7 | **F14** Kalender: Aktionen ins „+“-Menü, Legende kompakt, keine abgeschnittenen Labels | Behebt sichtbaren Mangel, schafft Platz für Tagesdetail | S |
| 8 | **F11** Leere Tage verdichten (Zeit-Tab) | Halbiert Scrollhöhe der Woche, ruhigeres Bild | S |
| 9 | **F36 + F04** Begriffsbereinigung (Zeitabschnitt/Eintrag, bewertet/erfasst, vorläufig erklären) | Verständlichkeit ohne Code-Umbau (Katalog) | S |
| 10 | **F38/F39** Widgets/Live Activity: konsistent h:mm, Fahrt ≠ Arbeitstagbalken, Rendering-Modus | Sichtbare Qualitätsmerkmale außerhalb der App, aktuell nur Galerie geprüft | M |

## 5. Quick Wins (je ≤ 1 Tag, geringes Risiko)

1. F02 Tab-Symbole tauschen (Heute: `timer`/`clock`, Zeit: `list.bullet.rectangle`).
2. F04/F36 Katalogtexte vereinheitlichen (nur `Localizable.xcstrings`, kein Code).
3. F10 Delta nur für Vergangenheit/heutigen Tag (eine Bedingung in `TimeView.swift`).
4. F14 Legende aus dem Kalender entfernen oder hinter Info-Taste; Chip-Beschriftung nicht kürzen.
5. F17 Warnbanner im Urlaub in neutrale Karte mit Knopf umwandeln.
6. F18 „Verfügbar / Nach Planung / Noch frei“ zu zwei Zahlen reduzieren.
7. F22 Datumszeile Sentence Case, `lineLimit(1)`.
8. F23 `.system(size: 10)` in Widgets auf Text-Style ≥ `caption2`.
9. F26 VoiceOver-Label der Uhr minutengenau und mit „läuft seit“.
10. F38 Sekunden aus „Erfasst“ im Medium/Large-Widget nehmen.

## 6. Bewusst so lassen (Stärken, nicht zerstören)

- **Eine Hauptaktion pro Karte, Stopp = rot, Start = Akzent** (`[S] ux1-iph-today.png`, `iph-dark-today-running.png`). Sofort lesbar, entspricht HIG.
- **Große tabellarische, gerundete Ziffern** und `h:mm`-Konvention – die Uhr ist ein Markenelement.
- **Design-Tokens, Kontrasttests (≥ 4,5:1), Akzentableitung, Reduce-Transparency-Fallback** (`[D] DESIGN-NATIVE.md`, 31 Design-Tests). Besser als die meisten Vorbilder.
- **Artenfarben mit Symbol und Namen** (Information nie nur über Farbe) in Zeile und Chip.
- **Zentrale Haptik-Schicht** mit Drossel und Opt-out, **ein** Ort für Bedeutungen.
- **Z1-Entscheidung „Kalender wie Apple Kalender“** (Monatsraster mit Punkten, Detail darunter): richtige Vorbildwahl.
- **S2-Gruppierung der Einstellungen** (Arbeit / Automatik / Info, Technik in Unterseiten): Richtung stimmt.
- **Seitenleiste auf iPad/Mac mit Gruppen und Fußzeile**, Timer in der Mac-Werkzeugleiste, Menüleisten-Extra und Tastaturkürzel (AD1).
- **Live-Activity-Schutzmaßnahmen** (deckende Füllungen, Clamp, Stresstests; LA2/LA3). Nicht für „mehr Glas“ riskieren, solange Gerät ungeprüft.
- **Watch: Snapshot-zuerst und Offline-Warteschlange** (A12) – Technik, die Nutzer nicht sehen, aber merken.

## 7. Offene Fragen an den Nutzer (nummeriert)

1. Soll „Urlaub“ ein eigener Tab bleiben oder Teil des Kalenders werden (F01)?
2. Sollen Krank/Urlaub-Schnellaktionen auf „Heute“ bleiben (F08)?
3. Darf die Heute-Karte die Differenz am Tagesbeginn ausblenden (F05/F10)?
4. Welches Wort gilt: „Zeitabschnitt“, „Eintrag“ oder „Zeitraum“ (F04)?
5. Soll es ein kurzes Onboarding geben, und soll ein Standardserver vorbelegt sein (F34/F35)? Das berührt die Entscheidung über Selbsthoster versus Hosting-Angebot.

### Entscheidungen des Nutzers (20.10.2026)

- F30 Haptik: Stufe „Dezent“ gefällt, bleibt Standard.
- Frage 1: Urlaub darf Teil des Kalenders werden (Variante A: Bereich „Planung“).
- Frage 2: Krank/Urlaub-Schnellaktionen dürfen auf „Heute“ bleiben, aber nur, wenn sie sonst nirgends schnell erreichbar sind.
- Frage 3: Differenz am Tagesbeginn darf ausgeblendet werden, wenn es besser aussieht.
- Frage 4: Wortwahl liegt beim Entwickler (einheitlich festlegen und in einem Glossar dokumentieren).
- Frage 5: Vorerst kein Onboarding, aber als Konzept dokumentieren.
- UX2: Variante A (Heute-zentriert) wird umgesetzt.

## 8. Nicht geprüft / Risiken dieser Analyse

- Alle Gerätethemen (Haptik, echte Live Activity, Dynamic Island, VoiceOver, Fokus/Automatik) stehen nur auf Basis von Handoffs und Code; sie könnten besser oder schlechter sein.
- Z2 und PL1 ändern Zeit-Tab, Kalender und Planung; F10–F15 sollten dort abgeglichen werden, bevor jemand sie umsetzt.
- Kontrastaussagen (F16) sind nicht gemessen; die Aussage „Kontraste ≥ 4,5:1“ stützt sich auf die Tests im Design-Paket, nicht auf Bildmessung.
- Keine Performancemessung (F43).
