# Handoff LA7-apple: Smart-Stack-Karte dunkel und aufgeräumt

Branch `la7-watch-card` (von `main` b5d5d11), 29.10.2026. Nicht gemergt, nicht gepusht, keine Build-Erhöhung, kein Upload.

## Ursache der hellen Karte (Sicherheit: hoch, aber nur indirekt belegt)
Der Nutzer-Screenshot zeigt eine helle graugrüne, durchscheinende Karte. Die Tönung war ein dynamisches `UIColor` (Q1/N2), das nach dem Erscheinungsbild auflöst. N2 hat nur die **dunkle** Variante geändert. Die **helle** Variante (Helligkeit 0,96, Alpha 0,82, Farbton des Akzents mit Sättigung x 0,1) über schwarzem Zifferblatt ergibt exakt dieses helle Graugrün. Auf der Uhr wurde also die helle Variante aufgelöst (die Uhr rendert den gespiegelten Teil nicht mit dem Erscheinungsbild des iPhones) und zusätzlich war sie durchscheinend. Belege: Screenshot (Farbe passt rechnerisch zur hellen Variante), Apple-Forum 799696 (`activityBackgroundTint` löst Hell/Dunkel nicht verlässlich) und 825061 (Tönung im Smart Stack auf iOS 26 nicht wie erwartet; Workaround: eigene Hintergrundfarbe in der Ansicht, Modifier behalten). Eine Apple-Dokumentation zur Semantik auf watchOS wurde nicht gefunden. Direkt am Gerät nicht verifiziert.

## Geändert
- Kern: `LiveActivityTint.watchCard(style:hue:saturation:brightness:)`: statisch (nie dynamisch), **deckend** (Alpha 1), immer dunkel (Dezent 0,11, Neutral 0,10, Farbig 0,14 bis 0,22) mit Farbhauch. Test `watchCardIsOpaqueAndDarkForEveryStyle`.
- `TimetrackWidgetIOS.swift`: Familie `.small` bekommt `watchCardColor` als `activityBackgroundTint` plus `activitySystemActionForegroundColor(.white)`; `.medium`/iPhone-Sperrbildschirm behält die Q1/N2-Tönung (unverändert, konsistent).
- `LiveActivitySmall` zeichnet dieselbe Farbe zusätzlich selbst als Hintergrund (greift auch, wenn der Tönungsmodifier ignoriert wird).
- Layout (Karte ca. 175 x 73 pt), von oben: Beschriftung 11 pt (Status-Symbol und Text links, Feierabend/Schätzung rechts, kürzt am Ende; Statustext hat Vorrang), Uhr 22 pt rund/halbfett/weiß mit tabellarischen Ziffern plus zwei runde Knöpfe (32 pt gezeichnet, **36-pt-Tippfläche**), Fortschrittskapsel 5 pt in Akzentfarbe auf blasser Spur (auf Kapsel zugeschnitten, blendet den Endknopf aus). Innenrand 12 / 5 pt, drei Breitenstufen (>= 170 / 150 / darunter).
- Neu: ab Kartenhöhe 92 pt ein großzügiges Layout: Uhr 34 pt, Kapsel 6 pt, zwei **44-pt**-Kapselknöpfe in voller Breite.
- Always-On (`isLuminanceReduced`): Knöpfe nur Umriss, Text 90 %, Kapsel 70 %, schwarzer Grund.
- 44 pt in der Standardkarte nicht möglich: 73 pt Höhe fassen Beschriftung, Uhr und Kapsel nicht mit 44-pt-Knöpfen, und 2 x 44 pt Knöpfe ließen der Uhr nur ca. 59 pt Breite. Daher 36 pt dort; Abweichung vom Wunsch bewusst.
- Galerie `LiveActivityWatchPreview` (`TT_DEV_WIDGET_GALLERY=running-live TT_DEV_LA_WATCH=1`): laufend, pausiert, Fahrt, ohne Plan, 45/41 mm, großzügig, Accessibility 3, Always-On (laufend/pausiert), alles auf Schwarz. Lange Ortsnamen kommen in der Karte nicht vor (nur Art/Status/Ende); Kürzung wird mit Accessibility 3 gezeigt.

## Prüfung
Kerntests (`swift test --build-system native --no-parallel`): 896 bestanden. Unsignierte Builds: TimetrackIOS (Simulator, enthält die Watch-App) und TimetrackMac: BUILD SUCCEEDED. Nach der letzten Änderung (Statustext erst ab 165 pt Kartenbreite, damit "Feierabend" bei 160 pt nicht abgeschnitten wird) erneut gebaut: BUILD SUCCEEDED. Screenshots: `docs/screenshots/la7-watch-running.png`, `la7-watch-green.png`.

## Nicht am Gerät geprüft
- Ob die Uhr die helle Variante wirklich aus dem dynamischen Farbwert gezogen hat (Hypothese passt rechnerisch, ist aber nicht per Konsole belegt) und ob der deckende Ton jetzt ankommt; Fallback ist der selbst gezeichnete Hintergrund.
- Ob die Uhr rund um die Karte einen eigenen Rand/Material zeigt, Always-On-Verhalten, Tippflächen 36 pt, Endknopf der Kapsel.
- Falls weiterhin hell: Systemmaterial überlagert die Tönung; dann nur `watchCard` / Hintergrund prüfen.
