# IC1 – Weitere App-Symbole (Motive und Hintergründe)

Anlass (Nutzerwunsch): nicht nur andere Akzentfarben, sondern andere Motive und Hintergründe. Branch `ic1-icons`. **Build-Nummer nicht erhöht, nichts hochgeladen.** Fokus-/Standortpakete unberührt.

## Ergebnis
- Zehn neue Alternativ-Symbole als Icon-Composer-Dokumente (`Icons/Timetrack*.icon`), erzeugt von `scripts/icons/motif_icons.py` (SVG-Ebenen, nur programmatisch gezeichnet; `build_icons.py` ruft das Skript auf, rendert Vorschauen mit ictool und die Übersicht `Icons/preview-variants.png`, prüft `project.yml`). Details und Tabelle: `docs/ICONS.md`, Abschnitt IC1.
- Varianten: Zifferblatt Hell, Zifferblatt Dunkel, Stoppuhr Verlauf, Timer-Ring Mesh, Sanduhr Warm, Balken Monochrom, Haken Grün, Monogramm T Getönt, Monogramm C Mesh (Chronolog), Feierabend Abendrot.
- Liquid Glass: Dokument-`fill` als Hintergrund, getrennte Vordergrundebenen; Mesh-Hintergründe als eigene randlose Ebene in einer zweiten Gruppe. Gesichtet bei 220/60/40 px sowie Default, Dark, TintedLight, TintedDark.
- `project.yml`: Ressourcen und `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` erweitert (16 Alternativen insgesamt, Bundle-Größe: Icons 0,9 MB, Vorschauen 0,7 MB).
- Auswahl (`Sources/iOS/AppIconSettingsSection.swift`): `IconAccent` heißt jetzt `AppIconChoice` (Gruppe, Hintergrund); Gruppen Klassik, dann je Motiv, als umbrechender Fluss von Kacheln (60 pt, Hintergrundname darunter, Auswahlrahmen in der Variantenfarbe). Neue Varianten stammen aus `IconCatalog.generated.swift` (generiert). Vorschaubilder aus denselben `.icon`-Dokumenten.
- Das Symbol bleibt unabhängig vom App-Akzent.

## Tests
`AppIconSwitchTests.testSwitchAppIcon` (Simulator iPhone 18 Pro, Wegwerf-Backend): Primär sicherstellen, Abendrot wählen, Zifferblatt Dunkel wählen, zurück zu Primär; prüft jeweils den Auswahlzustand. Bestanden (45 s). Aufruf wie bei den anderen UI-Tests mit `TEST_RUNNER_TT_DEV_SERVER`/`TEST_RUNNER_TT_DEV_COOKIE`. Der Test tippt auf den Navigationstitel, damit der Unterbrechungsmonitor die Systemmeldung des Symbolwechsels schließt. Kern-/Design-Tests unverändert (keine Logik geändert, nicht erneut gelaufen). Screenshots: `docs/screenshots/ic1-icon-picker-top.png`, `ic1-icon-picker-bottom.png`.

## Bekannte Grenzen
- Dunkel-/Getönt-Spezialisierungen ignorieren die Werkzeuge (siehe ICONS.md); Hell-Varianten (Zifferblatt Hell, Monogramm T) wirken in Getönt-Dunkel blass, bleiben aber erkennbar. Mittlere Tinte als Kompromiss.
- Echter Homescreen auf dem Gerät (60 pt, Dunkel/Getönt/Klar) nicht geprüft.
- Das macOS-/watchOS-Symbol bleibt das primäre; Alternativen gibt es nur auf iOS/iPadOS.

## Offene Fragen
1. Welche Varianten sollen bleiben (Zehn sind ein Vorschlag, Namen/Farben nicht abgestimmt)?
2. Soll das Monogramm C (Chronolog) das App-Store-Symbol-Kandidat werden?
3. Soll der In-App-Akzent künftig optional dem Symbol folgen (bisher bewusst getrennt)?
