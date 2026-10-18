# App icons (A6b, redesigned in A6c)

## Design
Dark navy surface (subtle top-to-bottom gradient `#1F2A4D` to `#0A0F22`), a thick **closed** ring with a vertical accent gradient (lighter at the top, stronger at the bottom) and two white rounded hands forming an "L" (12 and 3 o'clock). Reference look: user screenshot of an icon with an open ring; here the ring is closed.

## Layers (Icons/source/*.svg, 1024x1024)
- `ring.svg`: circle r=262, stroke 92, SVG linear gradient (userSpaceOnUse), blue default.
- `hands.svg`: white L path, stroke 56, round caps/join.
- `background.svg`: preview of the surface; in the `.icon` it is the document `fill` (linear-gradient).
The per-variant SVGs are generated into each bundle's `Assets/`.

## Accents (single source: `ACCENTS` in scripts/icons/build_icons.py, mirrored in `IconAccent.accents`)
The light tone is derived in OKLCH from the strong tone: lightness +0.13, chroma x0.9, same hue (sRGB gamut-clamped).

| Label | Bundle | Strong | Light |
|---|---|---|---|
| Blau (primary) | TimetrackPrimary | #2563EB | #5E93FC |
| Türkis | TimetrackTeal | #0EA5A4 | #61CDCB |
| Violett | TimetrackViolet | #7C3AED | #9D79FE |
| Grün | TimetrackGreen | #16A34A | #60CA79 |
| Orange | TimetrackOrange | #F97316 | #FEB692 |
| Rosa | TimetrackPink | #EC4899 | #FE91BF |
| Hell | TimetrackLight | #2563EB | #5E93FC (light surface, dark hands) |

The in-app accent is NOT wired to these yet; `IconAccent.accents` (Sources/iOS/AppIconSettingsSection.swift) is ready to drive it.

## Regenerate
`python3 scripts/icons/build_icons.py` rewrites all `Icons/*.icon`, `Icons/source`, the picker previews (`Sources/iOS/IconPreviews.xcassets`, rendered with ictool at 180 px) and `Icons/preview-variants.png` (rows = variants, columns = Default, Dark, TintedDark, TintedLight; needs Pillow, otherwise skipped). Do not hand-edit generated files.

## Schema / rendering findings
- Document `fill` accepts `{"linear-gradient": [c1, c2], "orientation": {"start":{x,y},"stop":{x,y}}}` and SVG layers keep their `linearGradient`s (verified with ictool and on a simulator).
- Layers use `glass: false`: with glass the ring looked washed out compared to the reference.
- ictool 27 and actool ignored the `image-name-specializations` / `fill-specializations` (dark, tinted) in tests (a red test specialization did not show; the compiled catalog contains no specialization vectors). The files still carry them (harmless), but do not rely on them. Consequences: Dark appearance uses the system derivation (looks right on the simulator: navy surface, blue ring, white hands); the "Hell" variant has dark hands that become hard to see in Dark/Tinted renditions (see handoff).
- The "dark hand in tinted" observed in A6b is the system mapping white to the tint colour (dark tint = darker). With a gradient ring in TintedDark the ring is dim and the hands carry the tint colour; acceptable, not a bug.
- Preview: `ictool X.icon --export-image --output-file o.png --platform iOS --rendition Default|Dark|TintedLight|TintedDark --width N --height N --scale 1 [--tint-color --tint-strength]`.

## Build integration
project.yml (`# A6b`/`# A6c`): `.icon` files are resources; `ASSETCATALOG_COMPILER_APPICON_NAME: TimetrackPrimary` on all targets; iOS also lists the alternates. Picker: `AppIconPickerSection` in `Sources/iOS/AppIconSettingsSection.swift` (uses preview image sets because UIKit cannot load alternate icon images).

## IC1: Motiv- und Hintergrundvarianten
Zehn zusätzliche Alternativ-Symbole, gruppiert nach Motiv; Quelle `scripts/icons/motif_icons.py` (`VARIANTS`; `build_icons.py` ruft es mit auf; erzeugt auch `Sources/iOS/IconCatalog.generated.swift`). Alles ist programmatisch gezeichnet (SVG-Ebenen, keine fremden Vorlagen). Jede Variante ist ein Icon-Composer-Dokument: Dokument-`fill` (Verlauf) als Hintergrund, getrennte SVG-Vordergrundebenen, bei Mesh zusätzlich eine randlose Hintergrundebene (radiale Verläufe) in einer eigenen Gruppe.

| Gruppe (Motiv) | Hintergrund | Bundle |
|---|---|---|
| Zifferblatt | Hell | TimetrackClockLight |
| Zifferblatt | Dunkel (orange Sekundenzeiger) | TimetrackClockDark |
| Stoppuhr | Verlauf (Cyan zu Indigo) | TimetrackStopwatch |
| Timer-Ring | Mesh (Türkis/Indigo/Magenta) | TimetrackTimer |
| Sanduhr | Warm (Bernstein zu Braun) | TimetrackHourglass |
| Balken | Monochrom | TimetrackBars |
| Haken | Grün (Verlauf) | TimetrackCheck |
| Monogramm T | Getönt (helles Lavendel) | TimetrackMonogramT |
| Monogramm C (Chronolog) | Mesh (Violett/Cyan/Magenta) | TimetrackMonogramC |
| Feierabend | Abendrot (Sonne über Horizont) | TimetrackSunset |

Regeln: Motive bleiben im mittleren Bereich, Strichstärken mindestens 28 px (bei 1024), damit sie bei 60 pt lesbar sind (gesichtet bei 220, 60 und 40 px). Helle Hintergründe nutzen mittlere Tinte (Schiefer, Indigo), weil die Systemableitung für Dunkel die Ebenen nicht umfärbt (Spezialisierungen werden ignoriert, siehe oben); im Getönt-Dunkel-Rendering sind Hell-Varianten blass, aber erkennbar. `build_icons.py` warnt, wenn `project.yml` ein Bundle nicht als Ressource und in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` führt. Vorschauen im Raster stammen aus denselben `.icon`-Dokumenten (ictool, 180 px) in `IconPreviews.xcassets`.

Auswahl: `AppIconPickerSection` zeigt Gruppen (Klassik = Akzentfarben, dann je Motiv) als Raster; die Zeile unter der Kachel nennt den Hintergrund. Das Symbol bleibt unabhängig vom App-Akzent. UI-Test: `AppIconSwitchTests`.
