# Handoff AD1: Mac- und iPad-gerechte Oberfläche (Shell, Navigation, Einstellungen, Menüs)

Branch `ad1-adaptive-mac-ipad` (main inkl. S2/OT1/V3/L4 eingemergt), 20.10.2026. Nicht gepusht, Build-Nummer unverändert, kein Upload. Inhalts-Views von Z1 (Zeit iOS) und V3 (Urlaub) wurden nicht angefasst.

## Inventur (Bilder `docs/screenshots/ad1-before-*`)
- **Mac** (Fensterabbild 1280x800): Es gab schon `NavigationSplitView`, `Settings`-Scene und Menüleisten-Extra, aber im Stil einer gestreckten iPhone-App: Kartenstapel in einer `ScrollView` (Zeit-Tab), Einstellungen als Kartenseiten in zwei Tabs (520x700 fest), Menüleisten-Extra nur als reines Menü, nur zwei Befehlskürzel (Heute/Zeit), keine Suche, keine Mehrfachauswahl, keine Detailspalte, kein Timer in der Werkzeugleiste, Mindestgröße 760x480.
- **iPad** (Pro 13 und 11, quer/hoch): Seitenleiste schon vorhanden (`horizontalSizeClass == .regular`), Kompakt (Split View/Slide Over) wird zur Tab-Leiste. Es fehlten Tastaturkürzel/Menü, Gruppierung der Seitenleiste, Zeitanzeige bei laufendem Timer; Einstellungen laufen als eine breite Liste.

## Konzept und Prioritäten (Begründung)
1. **Mac-Shell** (größter Hebel, weil der Eindruck „große iOS-App“ von Navigation und Einstellungen kommt): gruppierte Seitenleiste, Timer-Knopf in der Werkzeugleiste auf jedem Bildschirm, Mindestgröße 900x560.
2. **Mac-Einstellungen** als echte Settings-Scene mit Formularen (`Form`/`.grouped`) und vier Tabs.
3. **Menüs und Kürzel** (Mac zuerst, iPad mit denselben Kürzeln über die Hardware-Tastatur).
4. **Menüleisten-Extra** als Fenster-Panel mit laufender Uhr.
5. **Mac „Zeit“** als Liste mit Mehrfachauswahl, Suche, Kontextmenü, Inspector.
6. **iPad**: Seitenleiste gruppieren, Zeitanzeige, Pointer-Hover, Tastaturkürzel.
Bewusst nicht gemacht (Begründung unten unter „Offen“): zweispaltige iPad-Einstellungen, Drag&Drop, Berichte/Planung-Module als Mac-Bildschirme (existieren nativ nicht).

## Umgesetzt
**macOS** (`Sources/Mac`)
- `RootView.swift`: Seitenleiste mit Abschnitten „Erfassen“ (Heute, Zeit) und „Planung“ (Kalender, Urlaub; nur mit Modul), Fuß mit Konto und laufender Uhr; Werkzeugleisten-Knopf Start/Stopp (zuletzt gewählte Art) auf jedem Bildschirm; Rückfall auf „Heute“, wenn das Modul Planung abgeschaltet wird.
- `TimetrackMacApp.swift`: `defaultSize` 1100x720, Mindestgröße 900x560; `UIState` mit `send(TimeCommand)`.
- `MacCommands.swift`: Menüleiste. Datei: Neuer Eintrag ⌘N. Bearbeiten: Suchen ⌘F. Menü „Zeit“: Timer start/stopp ⌥⌘T, Woche zurück/vor ⌥⌘←/→, Diese Woche ⇧⌘T, Neu laden ⌘R. Menü „Gehe zu“: Heute/Zeit/Kalender/Urlaub ⌘1–4 (Modul-abhängig). Darstellung: Informationen anzeigen (Inspector) ⌥⌘I.
- `SettingsView.swift`: Tabs Allgemein (Konto, Server, Module, Abmelden), Darstellung (unverändert), Arbeit (Arbeitsmodell-Blatt, Haptik), Info; 580x560, native `Form`.
- `MenuBarContent.swift`: `MenuBarExtra` im Fensterstil: Beschriftung zeigt bei laufendem Timer die tickende Zeit, Panel mit großer Uhr, Artenwahl, Start/Stopp, Tagesfortschritt, „Timetrack öffnen“, Beenden ⌘Q.
- `TimeView.swift`/`MacTimeInspector.swift`: Liste (`List(selection:)`) mit Tagesabschnitten, Mehrfachauswahl, Kontextmenü (Bearbeiten, Stornieren), Doppelklick/Return = Bearbeiten, ⌫ = Stornieren (ein Grund für alle ausgewählten), Suche in der Werkzeugleiste (Art, Notiz), Inspector (rechts, ein-/ausblendbar) mit Zeit, Dauer, **Rohzeit nur wenn abweichend**, Korrekturen, Prüfhinweis.
- Texte der neuen Mac-Oberfläche in eigener Tabelle `Sources/Mac/AD1.xcstrings` (kein Merge-Konflikt mit `Localizable.xcstrings`), Zugriff über `AD.s(...)`.
- DEBUG-Hilfen (`DebugSnapshots.swift`): `TT_DEV_WINDOW=BxH`, Bilder der Einstellungs-Tabs über einen Debug-Opener.

**iPadOS** (`Sources/iOS`)
- `RootView.swift`: Seitenleiste in Abschnitten Erfassen / Planung / Einstellungen (Kennungen `sidebar.*` unverändert), Fuß mit Konto und laufender Uhr, `hoverEffect` für den Zeiger; `AppSection.group` in `TimetrackIOSApp.swift`.
- `IOSCommands.swift` (neu): Menü „Zeit“ (Timer ⌥⌘T, Neu laden ⌘R) und „Gehe zu“ ⌘1–5; wirkt mit Hardware-Tastatur und im iPadOS-Menü. Texte in `Sources/iOS/AD1.xcstrings`.
- `Tests/iOSUI/AdaptiveShotTests.swift` (neu): Bilder aller Bereiche quer/hoch für Vorher/Nachher.

Geteilte Dateien (Merge): `RootView.swift` und `TimetrackIOSApp.swift` (iOS, je wenige Zeilen), `project.yml` unverändert (neue Dateien liegen in bestehenden Ordnern; `xcodegen generate` neu erzeugt).

## Prüfung
- Kerntests 462 grün, Design 31 grün (`swift test --build-system native`). Builds macOS, iOS (Simulator), watchOS grün (unsigniert).
- iPad-UI-Tests (Pro 11): `SmokeTests` und `SettingsShotTests` grün; `ParityFlowTests` scheitert auf iPad Pro 11 an `settings.about` (nicht gefunden), **identisch auf unverändertem main** (Gegenlauf), also nicht von AD1 verursacht.
- Bilder: `docs/screenshots/ad1-before-*` und `ad1-after-*`: Mac (Heute, Zeit, Kalender, Urlaub, Einstellungs-Tabs; hell/dunkel), iPad Pro 13 hell/dunkel und Pro 11 hell (quer/hoch, alle Bereiche).
- **Bildgrenzen:** Das Mac-Bild ist die eigene Ansicht des Fensters (`cacheDisplay`, keine Bildschirmaufnahme-Berechtigung). **Seitenleiste, Werkzeugleiste, Suchfeld und Menüleisten-Extra sind darin nicht sichtbar** (Systemmaterial). Die Einstellungs-Tabs „dunkel“ zeigen ggf. noch hell (Appearance-Override der App).

## Nur am Gerät prüfbar / ungeprüft
- Mac: Aussehen von Seitenleiste, Werkzeugleiste (Timer-Knopf, Suche, Inspector-Schalter), Menüleisten-Extra (tickende Uhr in der Menüleiste, Fenster-Panel), Menüleisten-Befehle und Kürzel, Mehrfachauswahl mit Maus/Tastatur, ⌫ im Listenfokus, Inspector-Breite, Mindestgrößen, Fensterwiederherstellung, Liquid-Glass-Werkzeugleiste.
- iPad: Kürzel mit Hardware-Tastatur, Hover mit Zeiger, Stage Manager/Split View/Slide Over (Wechsel Seitenleiste/Tab-Leiste), Menü bei gehaltener ⌘-Taste.

## Offen / Fragen
1. Mac „Zeit“: Soll die Mehrfachauswahl auch **Zeiten korrigieren** (mehrere gleichzeitig verschieben) können? Aktuell nur Stornieren.
2. iPad-Einstellungen als Zwei-Spalten-Ansicht (Liste links, Detail rechts) wäre sinnvoll, berührt aber die S2-Struktur der Einstellungen; nicht umgesetzt.
3. iPad „Neuer Eintrag“ ⌘N und Woche vor/zurück über Tastatur fehlen, weil der iOS-Zeit-Tab (Z1) die Befehle konsumieren müsste; `UIState.newEntryRequest` existiert auf iOS, wird dort aber nicht ausgewertet. Vorschlag: Z1 oder Folgepaket.
4. Mac: Wochenübersicht, Wochenplanung und Urlaubsplanung (N1a/V3) und Berichtsheft existieren nur iOS; Mac-Seitenleiste zeigt sie nicht. Ob/wann nachziehen?
5. Drag&Drop (Zeitabschnitte zwischen Tagen verschieben, Anhänge auf Urlaub) nicht begonnen.
6. Mac-Zeit: Zeilendichte folgt weiter dem geteilten `SegmentRowCell` (iOS-Abstände); ein kompakter Modus braucht eine Änderung im Design-Paket.
