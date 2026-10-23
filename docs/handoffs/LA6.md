# Handoff LA6: Smart-Stack-Layout (`.small`) neu gestaltet

Branch `la6-watch-layout` (von `main`, Build 36), 23.10.2026. Nicht gemergt, nicht gepusht, keine Build-Erhöhung, kein Upload.

## Befund (Nutzer-Screenshot Build 36, 49 mm)
Die Karte misst nur ca. **175 x 73 pt** (Screenshot 350 x 147 px bei 2x), nicht 100 pt wie in LA3 angenommen. Vier Teile (Statuszeile, Uhr + Knöpfe, Balken, Beschriftung) passten nicht: Inhalt an den Rändern, Beschriftung am unteren Rand, Systembalken mit hellem Endpunkt.

## Neu (`LiveActivitySmall`, nur `Sources/WidgetShared/LiveActivityViews.swift`)
- Drei Zeilen, Innenrand 12 pt seitlich / 8 pt oben und unten: (1) Uhr führend (22 pt rund, Ziffern tabellarisch, weiß) und zwei runde Knöpfe (30 pt, Trefferfläche +1 pt, 4 pt Abstand); (2) schmaler 4-pt-Balken, auf Kapsel zugeschnitten (blendet den Endknopf des Systembalkens ab); (3) eine Beschriftungszeile 11 pt: Art-Symbol und Status links, "Feierabend hh:mm" rechts.
- Palette zurückhaltend: Pause/Weiter weiß-transluzent mit Haarlinie, Stopp rot (`TT.dangerFill`), Text weiß (Beschriftung 88 %); Tönung der Karte weiter aus `backgroundTint` (unverändert, daher iPhone-Sperrbildschirm unverändert).
- Größen: `Text(timerInterval:)` kürzt statt zu skalieren (schon LA3). Deshalb drei Breitenstufen per `GeometryReader` (>= 170 / >= 150 / darunter: Uhr 22/19/17 pt, Knöpfe 30/28/26 pt); in der schmalsten Stufe entfällt der Statustext (Symbol bleibt, Pause zeigt Pause-Symbol).
- Schriftgrößen fest (`.system(size:)`): wachsen nicht mit Dynamic Type, Karte hat feste Höhe; Mindestgröße 11 pt.
- Always-On (`isLuminanceReduced`): Knöpfe nur als Umriss, keine Füllung.
- Keine LA3-Konstrukte (`ViewThatFits`, `fixedSize`, Dynamic-Type-Kappung). Neu gegenüber LA2/LA5 nur `GeometryReader` und `isLuminanceReduced`; falls die Karte am Gerät wieder fehlt, zuerst diese beiden verdächtigen.
- DEBUG: `LiveActivityWatchPreview` zeigt Karten 175x73, 160x73, 148x68, 175x100, Accessibility 3, xSmall, Always-On und `.medium` (`TT_DEV_WIDGET_GALLERY=running-live TT_DEV_LA_WATCH=1`, optional `TT_DEV_LA_PAUSED=1`).

## Nicht geprüft / Grenzen
- Echtes Smart-Stack-Rendering nur am Gerät. Die Galerie ist eine Näherung (Tönung auf Grau). Die Breiten 41/45 mm (148/160 pt) sind geschätzt.
- Der Systemfortschrittsbalken (`ProgressView(timerInterval:)`) bleibt, weil nur er ohne Updates läuft; ob der Zuschnitt auf 4 pt den Endknopf auf der Uhr wirklich verbirgt und wie Spur/Füllung dort aussehen, ist am Gerät zu prüfen.
- `.medium` nutzt weiter das Banner; iPhone-Banner und Dynamic Island unverändert.

## Prüfung
Kerntests 555 bestanden; Builds unsigniert TimetrackIOS, TimetrackWatch, TimetrackMac: BUILD SUCCEEDED. Screenshots: `docs/screenshots/la6-watch-running.png`, `la6-watch-paused.png`.
