# App icons (A6b)

## Design
A calm 300 degree arc ("ruhiger Bogen", zinc) with a clock hand ("Zeiger") in the accent #2563EB on a calm zinc surface.
Few shapes, thick round-capped strokes so it reads at small sizes. The hand ends inside the arc.

## Layers (Icons/source/*.svg, 1024x1024)
- `background.svg`: surface colour (zinc-100). In the `.icon` it is the document `fill` (so dark specialization works), the SVG is the colour source/preview.
- `arc.svg`, `hand.svg`: the two glass layers (group has neutral shadow, specular on, translucency off).
- `highlight.svg`: optional marker, unused by default.

## Variants (Icons/*.icon)
| Bundle | Role | Description |
|---|---|---|
| TimetrackPrimary | primary | light surface, dark appearance specialized (zinc-900, lighter blue) |
| TimetrackLight | alternate | light surface everywhere |
| TimetrackDark | alternate | dark surface everywhere |
| TimetrackMono | alternate | black/white high contrast |
| TimetrackTeal | alternate | teal accent (#0D9488, dark #2DD4BF) |

All have a `tinted` image specialization with a white hand.

## Regenerate
`python3 scripts/icons/build_icons.py` rewrites every `Icons/*.icon` from `Icons/source`. Do not hand-edit generated bundles (or copy them out afterwards). Open one in Icon Composer (`open Icons/TimetrackPrimary.icon`) to inspect or tweak; port tweaks into the script.

## Schema notes
Derived from the Xcode icon template and Icon Composer's strings (`fill`, `fill-specializations`, `groups[].layers[].image-name(-specializations)`, `glass`, `shadow`, `specular`, `translucency`, `lighting`, `supported-platforms`). Render previews with
`.../Icon Composer.app/Contents/Executables/ictool X.icon --export-image --output-file o.png --platform iOS --rendition Default|Dark|TintedLight|TintedDark|ClearLight|ClearDark --width 512 --height 512 --scale 1`.

## Build integration
project.yml: `.icon` files are resources; `ASSETCATALOG_COMPILER_APPICON_NAME: TimetrackPrimary` on all three targets; iOS also `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`. The picker is `Sources/iOS/AppIconSettingsSection.swift`.

## Known limitation
In `TintedDark` the hand rendered dark in ictool previews (tinted image specialization seemingly not used there); tune after seeing it on a device.
