# Handoff LA3: Smart-Stack-Layout neu, deckenderer Live-Activity-Hintergrund

Branch `la3-watch-la` (von `main`, Build 13), 19.10.2026. Nicht gemergt, nicht gepusht, keine Build-Erhöhung, kein Upload.

## Ursache Watch-Layout (Nutzerfeedback Build 13)
Das LA2-Layout stapelte vier Zeilen (Uhr, Balken, Beschriftung, Knopfzeile). Die `.glass`-Knöpfe haben eigene Innenabstände und mindestens ca. 44 pt Höhe; Summe ca. 130 pt bei etwa 90 bis 100 pt verfügbarer Kartenhöhe. Der Stack quetschte zuerst die Textzeilen, daher wirkten die Knöpfe wie Verdränger.

## Neu (`LiveActivitySmall`)
- Drei Zeilen: Status (Symbol und "Läuft"/"Pausiert"), Uhr mit den zwei runden Knöpfen (34 pt, feste Größe) in einer Zeile, Balken mit einer Beschriftungszeile ("Feierabend ..."). Gesamthöhe ca. 90 pt.
- Knöpfe: feste Kreise mit transluzenter Füllung und heller Haarlinie (Glasoptik ohne `.buttonStyle(.glass)`).
- Uhr: `ViewThatFits` wählt 26/22/19/16 pt (ein Timer-Text kürzt sonst mit "..." statt zu skalieren; so in 41 mm zuerst gesehen und behoben).
- Dynamic Type auf `...large` begrenzt, damit die Karte nicht wächst. Ränder 14/8 pt.

## iPhone-Hintergrund
`LiveActivityTarget.backgroundTint` (statt Akzent bei 18 %): dunkel = Akzent auf 38 % Helligkeit bei 90 % Deckung, hell = Akzent entsättigt bei 78 % Deckung. Dynamische Farbe nach Erscheinungsbild.

## Prüfung
- `swift test --build-system native` (TimetrackCore): 380 Tests bestanden (Kern unverändert).
- Builds unsigniert: TimetrackIOS (mit Widget) und TimetrackWatch: BUILD SUCCEEDED.
- Debug-Galerie (`TT_DEV_WIDGET_GALLERY=running-live`, neu `TT_DEV_LA_WATCH=1`): `docs/screenshots/la3-watch-running.png`, `la3-watch-paused.png` (Karten für 41/45/49 mm, Accessibility 3, xSmall), `la3-iphone-running.png`.
- Echtes Smart-Stack-Rendering wurde nicht erreicht (benötigt gekoppelte iPhone-/Watch-Simulatoren mit laufender Activity); die Karten sind Näherungen (Breiten ca. 162/184/198 pt, Höhe 100 pt).

## Offen
- Am Gerät: Karte vollständig sichtbar, Knöpfe treffsicher, Hintergrundstärke Sperrbildschirm hell/dunkel; die Galerie zeigt keinen Systemmaterial-Hintergrund, die Deckung ist dort nur Näherung.
