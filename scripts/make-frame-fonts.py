#!/usr/bin/env python3
"""LA4: builds the two animation-frame fonts for the Live Activity icon (own vector drawings, no third-party assets).

Why a font: a Live Activity is rendered by the system without running SwiftUI animations; the only content that changes by itself
is `Text(timerInterval:)`. Its digits are the only moving part, so the digits 0-9 of these fonts are ten animation poses; the
view shows only the last digit (the seconds digit) and clips the rest. One pose per second, no activity updates, no app process.

usage: make-frame-fonts.py <output-dir> [--preview <png>]      (needs: pip install fonttools pillow)
Glyph box: 1000 x 1000 units, ascent 800 / descent 200, advance 1000 (so a Text of size N is an N x N square).
"""
import math, sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

DROP = 200  # design y (0 at the bottom of the box) -> font y = design y - DROP


def disc(cx, cy, r, n=20):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def stroke(p, q, w):
    """Thick line with round caps as one convex polygon."""
    (x1, y1), (x2, y2) = p, q
    a = math.atan2(y2 - y1, x2 - x1)
    pts = []
    for i in range(0, 11):  # cap at q
        t = a - math.pi / 2 + math.pi * i / 10
        pts.append((x2 + w / 2 * math.cos(t), y2 + w / 2 * math.sin(t)))
    for i in range(0, 11):  # cap at p
        t = a + math.pi / 2 + math.pi * i / 10
        pts.append((x1 + w / 2 * math.cos(t), y1 + w / 2 * math.sin(t)))
    return pts


def rect(x0, y0, x1, y1, r=0):
    if r <= 0:
        return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for i in range(0, 7):
            t = math.radians(a0 + 90 * i / 6)
            pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    return pts


def area(poly):
    return sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1])) / 2


def clockwise(poly):
    return poly if area(poly) < 0 else poly[::-1]  # TrueType: outer contours clockwise; overlaps union under non-zero fill


def blade(b, t, loaded):
    """Shovel blade at b, shaft towards t: a trapezoid plus an optional snow dome."""
    dx, dy = t[0] - b[0], t[1] - b[1]
    n = math.hypot(dx, dy)
    ux, uy = dx / n, dy / n          # along the shaft, towards the hands
    px, py = -uy, ux                  # across
    tip = (b[0] - ux * 30, b[1] - uy * 30)
    base = (b[0] + ux * 70, b[1] + uy * 70)
    poly = [(tip[0] + px * 55, tip[1] + py * 55), (tip[0] - px * 55, tip[1] - py * 55),
            (base[0] - px * 35, base[1] - py * 35), (base[0] + px * 35, base[1] + py * 35)]
    out = [poly]
    if loaded > 0:
        # snow heaped on the blade's upper side (away from the ground side = the side the blade's normal points to)
        nx, ny = (px, py) if py > 0 else (-px, -py)
        c = (tip[0] + ux * 40 + nx * 20, tip[1] + uy * 40 + ny * 20)
        out.append(disc(c[0], c[1], 50 * loaded))
        out.append(disc(c[0] + ux * 40 + nx * 10, c[1] + uy * 40 + ny * 10, 38 * loaded))
    return out


HIP, FOOT_A, FOOT_B, GROUND_Y = (310, 380), (230, 80), (400, 80), 80

# lean (deg, forward), blade, top of the shaft, snow on the blade (0..1), flying flakes (x, y, r)
SHOVEL = [
    (24, (650, 100), (420, 470), 0, []),
    (30, (730, 100), (450, 450), 0.5, []),
    (26, (700, 200), (410, 430), 1, []),
    (14, (650, 330), (350, 480), 1, []),
    (2, (620, 450), (300, 540), 1, []),
    (-4, (730, 520), (330, 470), 0.8, []),
    (6, (800, 480), (330, 400), 0, [(850, 560, 34), (905, 620, 26), (830, 640, 22)]),
    (12, (780, 400), (340, 370), 0, [(900, 650, 30), (950, 590, 22), (870, 700, 18)]),
    (18, (740, 280), (380, 400), 0, [(950, 520, 26), (905, 470, 20)]),
    (22, (690, 160), (410, 450), 0, [(965, 360, 18)]),
]


def shovel_pose(k):
    lean, b, t, loaded, flakes = SHOVEL[k]
    a = math.radians(lean)
    shoulder = (HIP[0] + 250 * math.sin(a), HIP[1] + 250 * math.cos(a))
    head = (shoulder[0] + 80 * math.sin(a), shoulder[1] + 80 * math.cos(a) + 25)
    hand1 = (b[0] + (t[0] - b[0]) * 0.62, b[1] + (t[1] - b[1]) * 0.62)
    hand2 = (b[0] + (t[0] - b[0]) * 0.9, b[1] + (t[1] - b[1]) * 0.9)
    knee_a = (HIP[0] - 20 + 14 * math.sin(a), 235)
    shapes = [
        stroke(HIP, shoulder, 90),                    # torso
        stroke(HIP, knee_a, 70), stroke(knee_a, FOOT_A, 66), stroke(FOOT_A, (FOOT_A[0] + 70, GROUND_Y), 60),
        stroke(HIP, (HIP[0] + 55, 235), 70), stroke((HIP[0] + 55, 235), FOOT_B, 66), stroke(FOOT_B, (FOOT_B[0] + 70, GROUND_Y), 60),
        disc(head[0], head[1], 62),                    # head
        stroke(shoulder, hand1, 56), stroke(shoulder, hand2, 56),  # arms
        stroke(b, t, 30),                              # shaft
    ]
    shapes += blade(b, t, loaded)
    shapes += [disc(x, y, r) for x, y, r in flakes]
    shapes.append(rect(60, 30, 940, 70, 18))          # ground line
    return shapes


def briefcase_pose(k):
    s = 1.0 + 0.07 * math.cos(2 * math.pi * k / 10) - 0.01  # breathing: 1.06 at k=0, 0.92 at k=5 (loops seamlessly)
    cx, cy = 500, 420

    def sc(poly):
        return [(cx + (x - cx) * s, cy + (y - cy) * s) for x, y in poly]

    parts = [
        rect(170, 160, 830, 340, 50), rect(170, 385, 830, 560, 50),  # case body in two halves (the gap is the seam)
        rect(445, 300, 555, 430, 20),                  # clasp bridging the seam
        rect(350, 540, 410, 760, 20), rect(590, 540, 650, 760, 20), rect(350, 710, 650, 770, 25),  # handle
    ]
    return [sc(p) for p in parts]


def build(path, family, poses):
    fb = FontBuilder(1000, isTTF=True)
    names = [".notdef", "space", "colon", "period"] + [f"d{i}" for i in range(10)]
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({0x20: "space", 0x3A: "colon", 0x2E: "period", **{0x30 + i: f"d{i}" for i in range(10)}})
    glyphs, metrics = {}, {}
    empty = TTGlyphPen(None).glyph()
    for n in (".notdef", "space", "colon", "period"):
        glyphs[n] = empty
        metrics[n] = (1000 if n != "colon" else 0, 0)
    for i in range(10):
        pen = TTGlyphPen(None)
        for poly in poses(i):
            pts = [(round(x), round(y - DROP)) for x, y in clockwise(poly)]
            pen.moveTo(pts[0])
            for p in pts[1:]:
                pen.lineTo(p)
            pen.closePath()
        glyphs[f"d{i}"] = pen.glyph()
        metrics[f"d{i}"] = (1000, 0)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": family, "styleName": "Regular", "uniqueFontIdentifier": f"{family}-LA4",
                       "fullName": family, "psName": family, "version": "Version 1.000"})
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200, sxHeight=500, sCapHeight=700)
    fb.setupPost()
    fb.save(path)


def preview(png):
    from PIL import Image, ImageDraw
    cell = 220
    img = Image.new("RGB", (cell * 10, cell * 2), "white")
    d = ImageDraw.Draw(img)
    for row, poses in enumerate((shovel_pose, briefcase_pose)):
        for k in range(10):
            ox, oy = k * cell, row * cell
            d.rectangle([ox, oy, ox + cell - 1, oy + cell - 1], outline="#cccccc")
            for poly in poses(k):
                d.polygon([(ox + x * cell / 1000, oy + (1000 - y) * cell / 1000) for x, y in poly], fill="black")
    img.save(png)


if __name__ == "__main__":
    out = sys.argv[1]
    build(f"{out}/TTFramesShovel.ttf", "TTFramesShovel", shovel_pose)
    build(f"{out}/TTFramesBriefcase.ttf", "TTFramesBriefcase", briefcase_pose)
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
