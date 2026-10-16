#!/usr/bin/env python3
"""Generate the Icon Composer documents (Icons/*.icon) from the SVG layers in Icons/source.

Usage: python3 scripts/icons/build_icons.py
The layers use reference colours (see REF); each variant recolours them per appearance.
Schema derived from Icon Composer's icon.json (see docs/ICONS.md).
"""
import json, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "Icons" / "source"
OUT = ROOT / "Icons"
REF = {"arc": "#A1A1AA", "hand": "#2563EB"}


def srgb(hexcolor):
    h = hexcolor.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


# Per variant: appearance -> (surface, arc, hand). "dark" omitted = same as default.
VARIANTS = {
    "TimetrackPrimary": {"default": ("#F4F4F5", "#A1A1AA", "#2563EB"),
                         "dark": ("#18181B", "#52525B", "#3B82F6")},
    "TimetrackLight": {"default": ("#FAFAFA", "#D4D4D8", "#2563EB")},
    "TimetrackDark": {"default": ("#18181B", "#52525B", "#3B82F6")},
    "TimetrackMono": {"default": ("#000000", "#FFFFFF", "#FFFFFF")},
    "TimetrackTeal": {"default": ("#F4F4F5", "#A1A1AA", "#0D9488"),
                      "dark": ("#18181B", "#52525B", "#2DD4BF")},
}


def recolor(layer, color):
    return (SRC / f"{layer}.svg").read_text().replace(REF[layer], color)


def build(name, spec):
    bundle = OUT / f"{name}.icon"
    if bundle.exists():
        shutil.rmtree(bundle)
    (bundle / "Assets").mkdir(parents=True)
    surface, arc, hand = spec["default"]
    # Appearances other than default get their own recoloured SVGs and fill.
    specs = {a: v for a, v in spec.items() if a != "default"}
    (bundle / "Assets" / "arc.svg").write_text(recolor("arc", arc))
    (bundle / "Assets" / "hand.svg").write_text(recolor("hand", hand))
    fills, arc_names, hand_names = [], [], []
    # Tinted: system tints luminance, so the hand must be light to stay visible (no fill override).
    specs["tinted"] = (None, "#A1A1AA", "#FFFFFF")
    for appearance, (s, a, h) in specs.items():
        (bundle / "Assets" / f"arc-{appearance}.svg").write_text(recolor("arc", a))
        (bundle / "Assets" / f"hand-{appearance}.svg").write_text(recolor("hand", h))
        if s:
            fills.append({"appearance": appearance, "value": {"solid": srgb(s)}})
        arc_names.append({"appearance": appearance, "value": f"arc-{appearance}.svg"})
        hand_names.append({"appearance": appearance, "value": f"hand-{appearance}.svg"})

    def layer(lname, image, spec_names):
        d = {"name": lname, "image-name": image, "glass": True}
        if spec_names:
            d["image-name-specializations"] = spec_names
        return d

    doc = {
        "fill": {"solid": srgb(surface)},
        "groups": [{
            "layers": [layer("Hand", "hand.svg", hand_names), layer("Arc", "arc.svg", arc_names)],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "specular": True,
            "translucency": {"enabled": False, "value": 0.5},
            "lighting": "combined",
        }],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    if fills:
        doc["fill-specializations"] = fills
    (bundle / "icon.json").write_text(json.dumps(doc, indent=2) + "\n")
    print("wrote", bundle.relative_to(ROOT))


if __name__ == "__main__":
    for n, s in VARIANTS.items():
        build(n, s)
