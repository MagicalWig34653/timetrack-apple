#!/usr/bin/env python3
"""Generate the Icon Composer documents (Icons/*.icon), the layer SVGs (Icons/source), the picker
preview assets (Sources/iOS/IconPreviews.xcassets) and a contact sheet (Icons/preview-variants.png).

Usage: python3 scripts/icons/build_icons.py   (previews/contact sheet need Icon Composer's ictool; the
contact sheet additionally needs Pillow and is skipped when it is missing)

Design: dark navy surface (document gradient fill), a closed ring with a vertical accent gradient
(lighter at the top, stronger at the bottom) and two white rounded hands (an "L": 12 and 3 o'clock).
The accent list below is the single source of truth (also documented in docs/ICONS.md).
"""
import json, math, shutil, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "Icons" / "source"
OUT = ROOT / "Icons"
PREVIEWS = ROOT / "Sources" / "iOS" / "IconPreviews.xcassets"
ICTOOL = Path("/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool")

# name, bundle, German label, strong accent (hex). The lighter tone is derived in OKLCH.
ACCENTS = [
    ("blue", "TimetrackPrimary", "Blau", "#2563EB"),
    ("teal", "TimetrackTeal", "Türkis", "#0EA5A4"),
    ("violet", "TimetrackViolet", "Violett", "#7C3AED"),
    ("green", "TimetrackGreen", "Grün", "#16A34A"),
    ("orange", "TimetrackOrange", "Orange", "#F97316"),
    ("pink", "TimetrackPink", "Rosa", "#EC4899"),
]
SURFACE_TOP, SURFACE_BOTTOM = "#1F2A4D", "#0A0F22"       # dark navy -> ink
LIGHT_TOP, LIGHT_BOTTOM = "#F8FAFC", "#DDE3EE"           # light surface option
HANDS_DARK_ON_LIGHT = "#0F172A"

# --- colour maths (sRGB <-> OKLCH) ---------------------------------------------------------------
def _lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def _gam(c): return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055

def hex_to_oklch(h):
    r, g, b = (_lin(int(h.lstrip("#")[i:i + 2], 16) / 255) for i in (0, 2, 4))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, bb), math.atan2(bb, a)

def oklch_to_rgb(L, C, H):
    a, b = C * math.cos(H), C * math.sin(H)
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)

def oklch_to_hex(L, C, H):
    while True:  # reduce chroma until the colour fits sRGB
        rgb = oklch_to_rgb(L, C, H)
        if all(-0.001 <= v <= 1.001 for v in rgb) or C < 0.001:
            break
        C *= 0.97
    return "#" + "".join(f"{round(min(1, max(0, _gam(max(v, 0)))) * 255):02X}" for v in rgb)

def light_tone(strong):
    """Lighter top-of-ring tone: same hue, +0.13 lightness, slightly less chroma."""
    L, C, H = hex_to_oklch(strong)
    return oklch_to_hex(min(L + 0.13, 0.93), C * 0.9, H)

def srgb(hexcolor):
    h = hexcolor.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"

# --- layer SVGs ----------------------------------------------------------------------------------
def ring_svg(top, bottom):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- Closed ring, centre (512,512), radius 262, stroke 92; vertical gradient light (top) -> strong (bottom). -->
  <defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="204" x2="0" y2="820">
    <stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient></defs>
  <circle cx="512" cy="512" r="262" fill="none" stroke="url(#g)" stroke-width="92"/>
</svg>
'''

def hands_svg(color):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- Two hands as an L: up to 12 (length 172) and right to 3 (length 128); round caps and join. -->
  <path d="M488 338 V542 H616" fill="none" stroke="{color}" stroke-width="56" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
'''

def gradient_fill(top, bottom):
    return {"linear-gradient": [srgb(top), srgb(bottom)],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}

def build(bundle_name, strong, light_surface=False):
    bundle = OUT / f"{bundle_name}.icon"
    if bundle.exists():
        shutil.rmtree(bundle)
    assets = bundle / "Assets"
    assets.mkdir(parents=True)
    top = light_tone(strong)
    hands_default = HANDS_DARK_ON_LIGHT if light_surface else "#FFFFFF"
    files = {
        "ring.svg": ring_svg(top, strong),
        "hands.svg": hands_svg(hands_default),
        # Tinted: neutral light ring below white hands. The system maps luminance onto the tint,
        # so the hands (white) stay the brightest element and the ring reads as a softer tone.
        "ring-tinted.svg": ring_svg("#E4E4E7", "#A1A1AA"),
        "hands-tinted.svg": hands_svg("#FFFFFF"),
    }
    ring_spec = [{"appearance": "tinted", "value": "ring-tinted.svg"}]
    hands_spec = [{"appearance": "tinted", "value": "hands-tinted.svg"}]
    fills = []
    if light_surface:  # dark appearance falls back to the dark surface with white hands
        files["hands-dark.svg"] = hands_svg("#FFFFFF")
        hands_spec.insert(0, {"appearance": "dark", "value": "hands-dark.svg"})
        fills.append({"appearance": "dark", "value": gradient_fill(SURFACE_TOP, SURFACE_BOTTOM)})
    for n, c in files.items():
        (assets / n).write_text(c)
    layer = lambda name, image, spec: {"name": name, "image-name": image, "glass": False,
                                       "image-name-specializations": spec}
    doc = {
        "fill": gradient_fill(*((LIGHT_TOP, LIGHT_BOTTOM) if light_surface else (SURFACE_TOP, SURFACE_BOTTOM))),
        "groups": [{
            "layers": [layer("Hands", "hands.svg", hands_spec), layer("Ring", "ring.svg", ring_spec)],
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
    return top

def render(bundle, out, rendition="Default", size=1024):
    subprocess.run([str(ICTOOL), str(bundle), "--export-image", "--output-file", str(out), "--platform", "iOS",
                    "--rendition", rendition, "--width", str(size), "--height", str(size), "--scale", "1"],
                   check=True, capture_output=True)

def main():
    SRC.mkdir(parents=True, exist_ok=True)
    variants = [(slug, name, label, strong, False) for slug, name, label, strong in ACCENTS]
    # Source previews of the layers (default blue) for reference.
    top = light_tone("#2563EB")
    (SRC / "ring.svg").write_text(ring_svg(top, "#2563EB"))
    (SRC / "hands.svg").write_text(hands_svg("#FFFFFF"))
    (SRC / "background.svg").write_text(
        f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- Surface preview only; in the .icon this is the document gradient fill. -->
  <defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{SURFACE_TOP}"/><stop offset="1" stop-color="{SURFACE_BOTTOM}"/></linearGradient></defs>
  <rect width="1024" height="1024" fill="url(#s)"/>
</svg>
''')
    tones = {}
    for slug, name, label, strong, light in variants:
        tones[slug] = build(name, strong, light)
    if not ICTOOL.exists():
        print("ictool not found: skipped previews")
        return
    if PREVIEWS.exists():
        shutil.rmtree(PREVIEWS)
    PREVIEWS.mkdir(parents=True)
    (PREVIEWS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for slug, name, label, strong, light in variants:
        d = PREVIEWS / f"IconPreview-{slug}.imageset"
        d.mkdir()
        render(OUT / f"{name}.icon", d / f"{slug}.png", size=180)
        (d / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"{slug}.png", "idiom": "universal", "scale": "3x"}],
            "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    try:
        from PIL import Image
    except ImportError:
        print("Pillow missing: skipped contact sheet")
        return
    renditions = ["Default", "Dark", "TintedDark", "TintedLight"]
    cell, pad = 150, 10
    sheet = Image.new("RGBA", (pad + len(renditions) * (cell + pad), pad + len(variants) * (cell + pad)), "#808080")
    tmp = ROOT / "Icons" / ".tmp.png"
    for r, (slug, name, *_rest) in enumerate(variants):
        for c, rend in enumerate(renditions):
            render(OUT / f"{name}.icon", tmp, rend, cell)
            im = Image.open(tmp).convert("RGBA")
            sheet.paste(im, (pad + c * (cell + pad), pad + r * (cell + pad)), im)
    tmp.unlink()
    sheet.save(OUT / "preview-variants.png", optimize=True)
    print("wrote Icons/preview-variants.png")

if __name__ == "__main__":
    main()
