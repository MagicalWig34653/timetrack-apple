# Handoff LA4: animiertes Arbeits-Symbol in der Live Activity

Branch `la4-animated-icon` (von `main`), 20.10.2026. Nicht gepusht, keine Build-Erhöhung, kein Upload.

## Was auf dem Gerät möglich ist, was nicht

Belege: Apple-Dokumentation „Displaying live data with Live Activities“ (Abschnitt Animationen), SDK 27.1 (`ActivityKit`/`WidgetKit`/`SwiftUI`-Interfaces), Versuch im Simulator.

**Nicht möglich**
- Fortlaufende SwiftUI-Animationen in der Live Activity. Dokumentation: „the system ignores any animation modifiers … and uses the system’s animation timing instead“; animiert wird nur beim Wechsel des Inhalts (Text: Blur-Übergang, Bilder/SF Symbols: Inhaltsübergang, `Text(timerInterval:)`). Im Always-On-Display keine Animationen (`isLuminanceReduced` beachten). `symbolEffect(.repeating)`, `TimelineView(.animation)` und `repeatForever` laufen dort nicht; in den WidgetKit-Interfaces des SDK gibt es keine API dafür.
- Bildwechsel per Update im Sekunden- oder Minutentakt: Updates kommen nur aus der App (im Hintergrund suspendiert, kein periodischer Lauf) oder per APNs (Budget, Drosselung; dieses Projekt hat keinen Push). Nicht tragfähig, daher nicht umgesetzt.
- Mein Simulatorversuch mit echten Symbol-Effekten in einer gestarteten Activity blieb ohne Ergebnis: der headless Simulator zeigt keine Dynamic Island/Sperrbildschirm-Activity in `simctl`-Screenshots. Die Aussage stützt sich daher auf die Dokumentation, nicht auf eigene Messung.

**Möglich (umgesetzt): Pose pro Sekunde über `Text(timerInterval:)`**
`Text(timerInterval:)` tickt systemseitig ohne App und ohne Updates (so läuft auch die Uhr der Activity). Eigene Schriften `TTFramesShovel` und `TTFramesBriefcase` (`Sources/Fonts`, eigene Vektorzeichnung, erzeugt von `scripts/make-frame-fonts.py`) belegen die Ziffern 0 bis 9 mit zehn Posen. Die Ansicht zeigt nur die letzte Ziffer der Arbeitsuhr (Sekunden-Einer, Rest per `clipped()` abgeschnitten): ein Bild pro Sekunde, Zyklus 10 s, Pause friert die Pose ein (`pauseTime`).
- Auf dem Gerät sichtbar (erwartet): Sperrbildschirm-Banner, Dynamic Island kompakt/minimal/expanded und Smart Stack zeigen die Figur, die sich im Sekundentakt bewegt. Das ist eine grobe Zeitlupen-Animation (1 Bild/s), keine flüssige.
- **Nicht am Gerät oder im echten Activity-Renderer geprüft.** Geprüft ist: die Schrift lädt, die Ziffernlogik und das Ticken in einer App-Ansicht (Debug-Galerie, Pose wechselt zwischen zwei Screenshots im Abstand von ca. 1 s). Offen: rendert das System den Timer-Text einer Activity mit der eigenen Schrift (Widget-Erweiterung, `UIAppFonts`)? Falls nicht, erschienen Ziffern statt Figur; deshalb ist der Standard **Aus**.
- Reduce Motion, Always-On-Display (`isLuminanceReduced`), Pause und andere Arten als Arbeit: ruhige Ruhepose bzw. das gewohnte Symbol.
- Batterie/Update-Limit: keine zusätzlichen Updates (null Budget); nur das Ticken, das die Uhr ohnehin hat. Die Einstellung löst genau ein `update` der laufenden Activity aus (lokal, kein Push).

**Alternative (c) in der App:** Die Vorschau in den Einstellungen läuft mit echter SwiftUI-Zeit (5 Posen/s, `TimelineView`). Das Heute-Tab/Jetzt-Leiste wurde nicht verändert (TimerHero liegt im Design-Paket, geteilt mit dem Mac); als Folgepaket möglich.

## Umsetzung
- Kern: `LiveActivityIconStyle` (`off` Standard, `briefcase`, `shovel`), `LiveActivityIconStore` (App Group, nur dieses Gerät), `LiveActivityTarget.iconStyle` (optional, alte Zustände dekodieren), `activeIconStyle` (nur laufende Arbeit), `iconFrame(at:)`. Wechsel des Stils ist ein `update`, kein Neustart (Reconciler getestet).
- Ansichten: `LiveKindIcon` ersetzt das Symbol in Banner, Island (alle Formen) und Smart Stack; `LiveIconPreview` in den Einstellungen.
- Einstellung: Einstellungen > Darstellung > „Live Activity: Symbol“ (Aus / Köfferchen / Schaufeln), Vorschau, ehrlicher Fußtext.
- Schriften als Ressourcen in App und Widget-Erweiterung, `UIAppFonts` in `project.yml`; Schriften neu erzeugen: `scripts/make-frame-fonts.py <Ausgabe> [--preview png]` (Python, fonttools, pillow). Lizenz: eigene Zeichnung, keine Fremdassets.
- Debug: `TT_DEV_LA_ICON=shovel|briefcase` (Galerie), `TT_DEV_LA_ICON_PAGE=1`, `TT_DEV_APPEARANCE_PAGE=1`.

## Prüfung
- `swift test --build-system native` (TimetrackCore): 471 Tests bestanden (davon 9 neu in `LiveActivityIconTests`: Standard, Frame-Ziffer, Pause, Auswahl nur Arbeit, Store, Dekodierung, Update statt Neustart).
- Builds unsigniert: siehe Abschlussmeldung (iOS inkl. Widget, Watch).
- Screenshots (klein): `docs/screenshots/la4-shovel-live.png`, `la4-briefcase-live.png`, `la4-settings.png`, `la4-frames.png` (alle zehn Posen).

## Checkliste auf dem Gerät
1. Einstellungen > Darstellung > Live Activity: Schaufeln wählen, Timer (Arbeit) starten: Figur im Banner, Island und Smart Stack sichtbar und wechselt sekündlich? Oder Ziffern/leer (dann Standard bei Aus lassen, Schrift im Extension-Bundle prüfen)?
2. Pause: Pose friert ein, Symbol Pause. Reise/Schule: Symbol wie bisher.
3. „Bewegung reduzieren“ an: ruhige Pose.
4. Stil in den Einstellungen wechseln bei laufender Activity: wechselt sofort.
5. Größe/Lesbarkeit der Figur im kompakten Island (22 pt).

## Offene Fragen
- Standard bleibt Aus, bis Punkt 1 am Gerät bestätigt ist; dann Standard auf Köfferchen oder Schaufeln?
- 1 Bild/s ist grob; eine zweite, um 0,5 s versetzte Timer-Ebene (halbe Sekunden) könnte 2 Bilder/s ergeben, unbestätigt.
