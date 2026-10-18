#!/usr/bin/env python3
"""IC1: motif x background app icon variants (Icon Composer documents).

Imported by build_icons.py (which renders the picker previews and the contact sheet); can also be run
alone: `python3 scripts/icons/motif_icons.py` rewrites Icons/Timetrack<Name>.icon and
Sources/iOS/IconCatalog.generated.swift (the Swift mirror of VARIANTS, keep generated).

Every variant is a proper Liquid Glass icon: a document fill (gradient) as background, plus separate
SVG foreground layers (and, for mesh backgrounds, a full-bleed background layer) so that the system can
derive the Light, Dark, Clear and Tinted renditions. All artwork is generated here (no external art).
"""
import json, math, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Icons"
SWIFT = ROOT / "Sources" / "iOS" / "IconCatalog.generated.swift"
C = 512  # canvas centre (1024 x 1024)


def srgb(hexcolor):
    h = hexcolor.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def fill(top, bottom, diagonal=False):
    o = ({"start": {"x": 0.15, "y": 0}, "stop": {"x": 0.85, "y": 1}} if diagonal
         else {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}})
    return {"linear-gradient": [srgb(top), srgb(bottom)], "orientation": o}


def svg(body, defs=""):
    d = f"<defs>{defs}</defs>" if defs else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
            f"{d}{body}</svg>\n")


def pt(angle_deg, r, cx=C, cy=C):
    """Point at clock angle (0 = 12 o'clock, clockwise)."""
    a = math.radians(angle_deg)
    return cx + r * math.sin(a), cy - r * math.cos(a)


def line(p, q, color, width, extra=""):
    return (f'<path d="M{p[0]:.1f} {p[1]:.1f} L{q[0]:.1f} {q[1]:.1f}" fill="none" stroke="{color}" '
            f'stroke-width="{width}" stroke-linecap="round" {extra}/>')


def arc(r, start, end, color, width, cx=C, cy=C, extra=""):
    """Stroked arc from clock angle start to end (clockwise)."""
    p, q = pt(start, r, cx, cy), pt(end, r, cx, cy)
    large = 1 if (end - start) % 360 > 180 else 0
    return (f'<path d="M{p[0]:.1f} {p[1]:.1f} A{r} {r} 0 {large} 1 {q[0]:.1f} {q[1]:.1f}" fill="none" '
            f'stroke="{color}" stroke-width="{width}" stroke-linecap="round" {extra}/>')


def vgrad(gid, top, bottom, y1=0, y2=1024):
    return (f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="0" y1="{y1}" x2="0" y2="{y2}">'
            f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>')


def mesh(blobs):
    """Mesh-like background: soft radial blobs (cx, cy, r, colour, opacity) over the document fill."""
    defs, body = "", ""
    for i, (cx, cy, r, col, op) in enumerate(blobs):
        defs += (f'<radialGradient id="m{i}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">'
                 f'<stop offset="0" stop-color="{col}" stop-opacity="{op}"/>'
                 f'<stop offset="1" stop-color="{col}" stop-opacity="0"/></radialGradient>')
        body += f'<rect width="1024" height="1024" fill="url(#m{i})"/>'
    return svg(body, defs)


# --- motifs: each returns a list of (layer name, svg) from top to bottom -----------------------------
def clock_light():
    ink, accent = "#64748B", "#2563EB"  # mid-tone ink stays visible in the system Dark rendition
    ticks = "".join(line(pt(a, 330), pt(a, 400 if a % 90 == 0 else 372), ink, 44 if a % 90 == 0 else 28)
                    for a in range(0, 360, 30))
    hands = (line((C, C), pt(305, 190), accent, 60) + line((C, C), pt(60, 270), accent, 44)
             + f'<circle cx="{C}" cy="{C}" r="36" fill="{accent}"/>')
    return [("Hands", svg(hands)), ("Ticks", svg(ticks))]


def clock_dark():
    ticks = "".join(line(pt(a, 330), pt(a, 400 if a % 90 == 0 else 372), "#E4E4E7", 44 if a % 90 == 0 else 28)
                    for a in range(0, 360, 30))
    hands = line((C, C), pt(305, 190), "#FFFFFF", 60) + line((C, C), pt(60, 270), "#FFFFFF", 44)
    second = (line(pt(200, 90), pt(20, 330), "#F97316", 22)
              + f'<circle cx="{C}" cy="{C}" r="40" fill="#F97316"/>')
    return [("Second hand", svg(second)), ("Hands", svg(hands)), ("Ticks", svg(ticks))]


def stopwatch():
    body = (f'<circle cx="{C}" cy="580" r="262" fill="none" stroke="#FFFFFF" stroke-width="72"/>'
            f'<path d="M452 168 H572" stroke="#FFFFFF" stroke-width="64" stroke-linecap="round"/>'
            f'<path d="M512 200 V262" stroke="#FFFFFF" stroke-width="56"/>')
    side = line(pt(48, 330, C, 580), pt(48, 372, C, 580), "#FFFFFF", 64)
    hand = line((C, 580), pt(35, 168, C, 580), "#FDE047", 56) + f'<circle cx="{C}" cy="580" r="38" fill="#FDE047"/>'
    return [("Hand", svg(hand)), ("Case", svg(body + side))]


def timer_ring():
    track = f'<circle cx="{C}" cy="{C}" r="258" fill="none" stroke="#FFFFFF" stroke-opacity="0.2" stroke-width="96"/>'
    prog = arc(258, 0, 262, "url(#g)", 96)
    mark = f'<circle cx="{C}" cy="{C}" r="34" fill="#FFFFFF"/>'
    return [("Centre", svg(mark)), ("Progress", svg(prog, vgrad("g", "#FFFFFF", "#9FE7F5", 250, 770))),
            ("Track", svg(track))]


def hourglass():
    glass = ('<path d="M352 270 H672 C672 420 574 470 574 512 C574 554 672 604 672 754 H352 '
             'C352 604 450 554 450 512 C450 470 352 420 352 270 Z" fill="none" stroke="#FFFFFF" '
             'stroke-width="52" stroke-linejoin="round"/>'
             '<path d="M312 250 H712 M312 774 H712" stroke="#FFFFFF" stroke-width="64" stroke-linecap="round"/>')
    sand = ('<path d="M420 318 H604 C592 396 540 438 512 456 C484 438 432 396 420 318 Z" fill="#FDE68A"/>'
            '<path d="M512 560 L512 690" stroke="#FDE68A" stroke-width="14"/>'
            '<path d="M392 714 C440 650 584 650 632 714 V722 H392 Z" fill="#FDE68A"/>')
    return [("Sand", svg(sand)), ("Glass", svg(glass))]


def bars():
    heights, w, gap, base = [170, 250, 340, 430, 540], 92, 44, 770
    x0 = (1024 - (5 * w + 4 * gap)) / 2
    rects = "".join(f'<rect x="{x0 + i * (w + gap):.0f}" y="{base - h}" width="{w}" height="{h}" rx="30" '
                    f'fill="{"#FFFFFF" if i == 4 else "#8A8A93"}"/>' for i, h in enumerate(heights))
    return [("Bars", svg(rects))]


def check():
    ring = f'<circle cx="{C}" cy="{C}" r="330" fill="none" stroke="#FFFFFF" stroke-opacity="0.32" stroke-width="44"/>'
    tick = '<path d="M326 528 L464 664 L716 366" fill="none" stroke="#FFFFFF" stroke-width="112" stroke-linecap="round" stroke-linejoin="round"/>'
    return [("Check", svg(tick)), ("Ring", svg(ring))]


def monogram_t():
    ink, dot = "#4F46E5", "#EC4899"  # mid-tone indigo, readable on light and dark
    t = (f'<path d="M274 330 H750" stroke="{ink}" stroke-width="116" stroke-linecap="round"/>'
         f'<path d="M512 330 V690" stroke="{ink}" stroke-width="116" stroke-linecap="round"/>')
    accent = f'<circle cx="700" cy="696" r="52" fill="{dot}"/>'
    return [("Dot", svg(accent)), ("T", svg(t))]


def monogram_c():
    c = arc(290, 52, 308, "url(#g)", 112)
    hand = line((C, C), pt(90, 150), "#FDE047", 60) + f'<circle cx="{C}" cy="{C}" r="46" fill="#FDE047"/>'
    return [("Hand", svg(hand)), ("C", svg(c, vgrad("g", "#FFFFFF", "#C4B5FD", 220, 800)))]


def sunset():
    sun = '<path d="M322 590 A190 190 0 0 1 702 590 Z" fill="#FEF3C7"/>'
    horizon = ('<path d="M232 590 H792" stroke="#FFFFFF" stroke-width="44" stroke-linecap="round"/>'
               '<path d="M312 686 H712" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="40" stroke-linecap="round"/>'
               '<path d="M402 778 H622" stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="36" stroke-linecap="round"/>')
    return [("Sun", svg(sun)), ("Horizon", svg(horizon))]


# slug, bundle, motif key, motif (German), background (German), tile title, selection tint, fill, layers,
# optional full-bleed background layer
def _variants():
    return [
        dict(slug="clock-light", motif="Zifferblatt", background="Hell", tint="#2563EB",
             fill=fill("#FFFFFF", "#D5DCE8"), layers=clock_light()),
        dict(slug="clock-dark", motif="Zifferblatt", background="Dunkel", tint="#F97316",
             fill=fill("#27272A", "#050506"), layers=clock_dark()),
        dict(slug="stopwatch", motif="Stoppuhr", background="Verlauf", tint="#4F46E5",
             fill=fill("#22D3EE", "#4338CA", True), layers=stopwatch()),
        dict(slug="timer", motif="Timer-Ring", background="Mesh", tint="#06B6D4",
             fill=fill("#0B1226", "#050814"), layers=timer_ring(),
             backdrop=mesh([(250, 250, 620, "#14B8A6", 0.85), (800, 330, 560, "#6366F1", 0.8),
                            (560, 900, 640, "#EC4899", 0.7)])),
        dict(slug="hourglass", motif="Sanduhr", background="Warm", tint="#EA580C",
             fill=fill("#FDBA74", "#9A3412"), layers=hourglass()),
        dict(slug="bars", motif="Balken", background="Monochrom", tint="#71717A",
             fill=fill("#2B2B30", "#000000"), layers=bars()),
        dict(slug="check", motif="Haken", background="Grün", tint="#059669",
             fill=fill("#4ADE80", "#047857", True), layers=check()),
        dict(slug="monogram-t", motif="Monogramm T", background="Getönt", tint="#6366F1",
             fill=fill("#F1EEFF", "#C9C1F7"), layers=monogram_t()),
        dict(slug="monogram-c", motif="Monogramm C", background="Mesh", tint="#8B5CF6",
             fill=fill("#17123A", "#0A0720"), layers=monogram_c(),
             backdrop=mesh([(220, 200, 600, "#7C3AED", 0.9), (850, 280, 520, "#06B6D4", 0.55),
                            (700, 880, 620, "#DB2777", 0.8)])),
        dict(slug="sunset", motif="Feierabend", background="Abendrot", tint="#F97316",
             fill=fill("#6D28D9", "#FB923C"), layers=sunset()),
    ]


def _bundle_name(slug):
    return "Timetrack" + "".join(p.capitalize() for p in slug.split("-"))


VARIANTS = _variants()
for _v in VARIANTS:
    _v["bundle"] = _bundle_name(_v["slug"])
    _v["title"] = f'{_v["motif"]} {_v["background"]}'


def build(v):
    bundle = OUT / f'{v["bundle"]}.icon'
    if bundle.exists():
        shutil.rmtree(bundle)
    assets = bundle / "Assets"
    assets.mkdir(parents=True)
    layers = []
    for name, content in v["layers"]:
        fn = name.lower().replace(" ", "-") + ".svg"
        (assets / fn).write_text(content)
        layers.append({"name": name, "image-name": fn, "glass": False})
    groups = [{"layers": layers, "shadow": {"kind": "neutral", "opacity": 0.5}, "specular": True,
               "translucency": {"enabled": False, "value": 0.5}, "lighting": "combined"}]
    if v.get("backdrop"):
        (assets / "backdrop.svg").write_text(v["backdrop"])
        groups.append({"layers": [{"name": "Backdrop", "image-name": "backdrop.svg", "glass": False}],
                       "specular": False, "lighting": "individual"})
    doc = {"fill": v["fill"], "groups": groups, "supported-platforms": {"circles": ["watchOS"], "squares": "shared"}}
    (bundle / "icon.json").write_text(json.dumps(doc, indent=2) + "\n")
    print("wrote", bundle.relative_to(ROOT))


def write_swift():
    rows = "".join(
        f'        AppIconChoice(iconName: "{v["bundle"]}", previewAsset: "IconPreview-{v["slug"]}", '
        f'title: "{v["title"]}", group: "{v["motif"]}", background: "{v["background"]}", '
        f'strongHex: 0x{v["tint"].lstrip("#")}, lightHex: 0x{v["tint"].lstrip("#")}),\n' for v in VARIANTS)
    SWIFT.write_text(
        "// Generated by scripts/icons/motif_icons.py (IC1). Do not edit by hand.\n\n"
        "extension AppIconChoice {\n    /// Motif variants in display order (grouped by `group`).\n"
        f"    static let motifs: [AppIconChoice] = [\n{rows}    ]\n"
        f"    /// Alternate icon names for ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES check.\n"
        f'    static let motifBundleNames = "{" ".join(v["bundle"] for v in VARIANTS)}"\n}}\n')
    print("wrote", SWIFT.relative_to(ROOT))


def main():
    for v in VARIANTS:
        build(v)
    write_swift()


if __name__ == "__main__":
    main()
