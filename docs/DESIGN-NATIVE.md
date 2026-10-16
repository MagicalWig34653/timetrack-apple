# Native Designsprache (Apple-Clients)

Gilt für iOS/iPadOS, macOS und watchOS. Quelle der Gestaltung ist die PWA-Designsprache (Backend `docs/DESIGN.md`, ADR-0014):
Zinc-Neutrale, ruhiges Blau `#2563EB` als Standard-Akzent, wenig Farbe, Glas nur als Rahmen, große tabellarische Ziffern, Status als Chips mit Text.
Umsetzung: Swift-Paket `Packages/TimetrackDesign` (abhängig nur von `TimetrackCore`; keine Strings im Paket, Schlüssel liegen in den Katalogen der Apps).

## Tokens (`Tokens.swift`, Namensraum `TT`)

| Gruppe | Tokens |
| --- | --- |
| Flächen | `background` (hell F4F4F5 / dunkel 0C0C0E), `surface` (FFFFFF / 1A1A1E), `surfaceRaised`, `glassFallback`, `separator`, `cardBorder` |
| Text | `textPrimary`, `textSecondary`, `textTertiary` (Kontrast zu `background`/`surface` >= 4,5:1 in beiden Modi) |
| Status | `success`, `warning`, `danger` (unabhängig vom Akzent) |
| Arten | `kindWork` (sky), `kindTravel` (amber), `kindSchool` (violett) wie PWA-Tageszeitleiste; Abwesenheiten wie PWA `ABSENCE_CLASSES`: `kindVacation` (sky), `kindSick` (rose), `kindExcused` (teal), `kindOther` (violett), `kindHoliday` (amber) |
| Akzent | Standard `#2563EB`; lokale Wahl (siehe Abschnitt Akzent-System) per `.ttAppearance()` am App-Wurzelknoten (setzt `.ttTheme(accentHex:)` und `preferredColorScheme`); Komponenten lesen `@Environment(\.ttTheme)`: `accent` (Fläche), `onAccent` (Schrift auf Fläche), `ink` (Akzent als Text); Asset `AccentColor` je App (2563EB / 60A5FA) |
| Abstände/Radien | `TT.Space` (xs 4 ... xxl 32), `TT.Radius` (control 14, card 22, hero 28), Lesebreite `TT.contentWidth` 760 |
| Schrift | `TTFont`: Seitentitel/Abschnitt/Karte/Beschriftung/Meta/Eyebrow; Zahlen `stat`, `numeral` als gerundete Systemschrift mit tabellarischen Ziffern; alles skaliert mit Dynamic Type |

Dauern immer `h:mm` (`DurationFormat`); Timer `h:mm:ss`. watchOS kennt nur den dunklen Modus (dort wird der Dunkelwert verwendet).

## Komponenten

`Card`, `GlassCard`, `ListCard` (Trenner automatisch), `TTBackdrop`/`.ttScreenBackground()` (neutral mit zwei sehr weichen Akzent-Lichtern, damit Glas etwas zum Brechen hat),
`StatTile`, `StatusChip`, `KindBadge`/`KindGlyph`, `LiveDot`, `PrimaryButton`/`SecondaryButton` als `.ttPrimary`, `.ttDanger`, `.ttSecondary`,
`TimerHero` + `KindSelector`, `SegmentRowCell`, `ProgressRing`, `ProgressBar`, `SectionHeader`, `Eyebrow`, `EmptyState`, `HintBanner`, `ErrorBanner`,
`FormSection`/`FormRow` (+ `.ttField()`), `SkeletonBlock`/`SkeletonList`, `BrandMark`. `DesignGallery` zeigt alles mit Beispieldaten (Previews hell, dunkel laufend, große Schrift, feste Flächen).

## Regeln

1. Glas nur für Rahmen und Hero (Timer-Karte, Tab-/Seitenleiste, Sheets); Datenkarten und alle Schrift bleiben deckend. `ttGlass` nutzt `glassEffect`, bei Reduce Transparency (oder `\.ttSolidSurfaces`) eine deckende Fläche mit Rand.
2. Akzent nur für Hauptaktion, Auswahl, Navigation, Fokus; Statusfarben und Artenfarben sind davon unabhängig. Information nie nur über Farbe: Chips tragen Text, Zeilen den Artennamen.
3. Eine Hauptaktion je Karte; Stoppen ist `danger`, Starten `accent`. Sekundäres (Anmeldeart wechseln, Server wechseln) als leise Textaktion.
4. Bewegung sparsam: Ring/Übergänge `.smooth`, Live-Punkt pulsiert, Skeleton atmet; alles entfällt bei Reduce Motion. Haptik nur beim Start (`.start`) und Stopp (`.stop`) des Timers.
5. Accessibility-Größen: Raster/Zeilen wechseln auf eine Spalte (`isAccessibilitySize`), Kennzahlen skalieren herunter statt abzuschneiden, Kombinierte Elemente für VoiceOver.
6. iPad/Mac: Inhalt in Spalten statt Streckung (Heute zweispaltig, Zeit mit Wochenübersicht, Lesebreite begrenzt); iPhone: ein Strom aus Karten.
7. Texte Deutsch in den `Localizable.xcstrings` der Apps, Code Englisch. Neue Schlüssel mit `scripts/add-strings.py`.

## Akzent-System (A6d)

Seite "Darstellung" (`AppearanceSettingsPage` im Design-Paket; iOS: Einstellungen > Darstellung, macOS: Einstellungsfenster, Tab "Darstellung"). Akzentfarbe und App-Symbol werden getrennt gewählt; das eine ändert nie das andere.
- Auswahl: Blau, Türkis, Violett, Grün, Orange, Rosa (Farbtöne wie `IconAccent.strongHex`), Graphit `#52525B`, Eigene (`ColorPicker`). Seit A8 Kontoeinstellung (siehe Abschnitt Konto-Sync); UserDefaults (`appearance.accent`, `appearance.customHex`, `appearance.scheme`) bleiben Sofort-Cache und Offline-Rückfall.
- Erscheinungsbild System/Hell/Dunkel (`preferredColorScheme`). "Transparenz reduzieren" folgt nur der Systemeinstellung (Anzeige des Zustands, kein App-Schalter).
- Ableitung (`AccentDerivation`, wie PWA `accent.ts`): `accent` = gewählter Farbton (im Dunkelmodus aufgehellt, falls < 3:1 zum Grund, z. B. Graphit); `onAccent` = Weiß oder Schwarz mit >= 4,5:1 (Orange, Gelb tragen schwarze Schrift); `ink` = Akzent als Text/Symbol/Tint, in 5-%-Schritten Richtung Schwarz (hell) bzw. Weiß (dunkel), bis >= 4,5:1 auf allen App-Flächen und den getönten Chip-Hintergründen erreicht ist. Systemsteuerung (`tint`) nutzt `ink`. Tests: Kontrast über alle Voreinstellungen und Extremfarben.
- Konsequenz: Orange/Rosa/Türkis erscheinen als Text im Hellmodus dunkler (bräunlich/gedämpft) als die Fläche; das ist gewollt (Lesbarkeit).
- Konto-Avatar, Marke (`BrandMark`), Ringe, Glow, Chips, Auswahl folgen dem Akzent. Statusfarben und Artenfarben bleiben unabhängig.

## App-Icon und Start

`scripts/make-app-icon.swift` (CoreGraphics, ohne Abhängigkeiten) erzeugt `Sources/{iOS,Mac,Watch}/Assets.xcassets` (AppIcon, AccentColor, iOS LaunchBackground).
Motiv: offener Zeitbogen in Akzentblau mit Zeigern auf ruhigem dunklem Grund; macOS mit eingebauter Kachel und Schatten. Startbild: `UILaunchScreen` mit Hintergrundfarbe `LaunchBackground` (hell/dunkel). `BrandMark` zeichnet dasselbe Motiv in SwiftUI.
Nur ein Icon (kein dunkles/getöntes iOS-Icon), siehe Handoff.

## Prüfung

Screenshots (synthetische Daten, Wegwerf-Backend) unter `docs/screenshots/`; Liste und Befunde in `docs/handoffs/A6.md`.
Wiederholbar: `scripts/seed-throwaway.py` (Backend-Binary, Arbeitsverzeichnis, Port >= 18500) und `Tests/iOSUI/ScreenshotTests.swift` (`TEST_RUNNER_TT_DEV_SERVER`, `..._COOKIE`, `..._TT_SHOT_DIR`, `..._TT_SHOT_PREFIX`, optional `..._TT_SHOT_LANDSCAPE`).
macOS: Debug-Hook `TT_DEV_SNAPSHOT_DIR` (zusammen mit `TT_DEV_SERVER`/`TT_DEV_COOKIE`) schreibt die Fensteransicht als PNG; der Tester kann Bildschirmfotos hier nicht erstellen, und Glas sowie die Seitenleisten-Liste erscheinen in dieser Aufnahme nicht.
Paket-Test: `swift test` rendert mit `TT_GALLERY_OUT=<Ordner>` die Galerie als macOS-PNG (ohne Glas).

## Widgets (A7)

Home-Widgets (small/medium/large), Sperrbildschirm (circular/rectangular/inline), Live Activity, Kontrollzentrum-Schalter und macOS-Widgets nutzen dieselben Tokens (`TT.background`, `surface`, Artenfarben, `ProgressRing`, `KindGlyph`); Quelle `Sources/WidgetShared`.
Regeln: laufend = Artenabzeichen + systemseitiger `Text(timerInterval:)`, Stopp rot; Leerlauf = Ring Heute/Soll, Start im Akzent; große Zahlen gerundet/tabellarisch; Zeiten in der Zone des Arbeitsmodells; "Aktualisiert um hh:mm" nur wenn der Snapshot älter als 30 Minuten ist; Sperrbildschirm ohne eigene Farben (Vibrancy). Seit A8 tragen die Widgets den Konto-Akzent (`WidgetSnapshot.accentHex`, Ableitung `TTTheme`/`AccentDerivation` wie in der App; Start-Knopf `accent` + `onAccent`). Debug: `TT_DEV_WIDGET_GALLERY`. Details: `docs/handoffs/A7.md`.

## Konto-Sync des Akzents (A8)

Akzent und Erscheinungsbild gehören zum Konto (`GET/PATCH /me/preferences`, Vertrag v0.14.0, ADR-0020); App-Symbol und Transparenz bleiben geräteweit.
- Kern: `Preferences`, `PreferencesPatch`, `APIClient.getPreferences/updatePreferences`, `Account.preferences` (aus `GET /auth/session`), `AppearanceSync` (Abgleich, Entprellung 0,7 s, Wiederholung 30 s). `AppModel.appearance` ruft `connect` nach jeder geladenen Sitzung (Recovery: nur lesen).
- Regeln (wie P2-Handoff): Cache sofort; lokale ungesendete Änderung desselben Kontos gewinnt (Marke `appearance.pendingAccount`); sonst ersetzen Kontowerte den Cache; Erstmigration einmalig, wenn das Konto nie gespeichert hat, die lokale Wahl vom Standard abweicht und der Cache nicht einem anderen Konto gehört (`appearance.cacheOwner`); 400 verwirft die Marke, Netz/5xx/401/403/429 behalten sie; unbekannte künftige Akzent-IDs erscheinen als Blau und werden nicht zurückgeschrieben; ältere Server ohne `account.preferences`: rein lokal.
- ID-Zuordnung: `AccentChoice` = `AccentPreset` (Test). Native Farbtöne weichen bewusst von der PWA ab: Türkis `#0EA5A4` (PWA `#0D9488`), Orange `#F97316` (`#D97706`), Rosa `#EC4899` (`#DB2777`); Blau, Violett, Grün, Graphit gleich. Nur die IDs sind vertraglich.
- Darstellungsseite: eine Statuszeile (`SyncStatusLine`): synchronisiert / wird synchronisiert / nur auf diesem Gerät, wird gesendet sobald online / Fehlertext.
- Widgets/Komplikation: `WidgetSnapshot.accentHex` und `colorScheme` (additiv, optional, validiert). Widgets folgen dem Systemerscheinungsbild; `colorScheme` wird nur mitgeschrieben. Intents behalten den zuletzt geschriebenen Akzent.
