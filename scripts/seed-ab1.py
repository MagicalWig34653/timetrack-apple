#!/usr/bin/env python3
"""AB1: prepares a THROWAWAY backend (seed-throwaway.py + seed-vacation-v3.py) for the attachment and vacation request UI tests.

usage: seed-ab1.py <server-url> <session-token> <outdir>   (loopback only; all data is synthetic)
- uploads a synthetic AcroForm template ("Urlaubsantrag (synthetisch)") and a mapping in the PWA's format (PUT /vacation/request-form/...)
- writes sample files for TT_DEV_ATTACH_FILE into <outdir>: krankschein.pdf, foto.png, gross.txt (11 MiB: the server answers 413)
The employer's real form is never used here.
"""
import json, os, struct, sys, urllib.parse, urllib.request, zlib

server, token, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
assert server.startswith("http://127.0.0.1:") or server.startswith("http://localhost:")
base = server + "/api/v1"
headers = {"Cookie": f"tt_session={token}"}
os.makedirs(outdir, exist_ok=True)

csrf = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/auth/session", headers=headers)).read())["csrfToken"]

def put(path, data, content_type, extra=None):
    request = urllib.request.Request(base + path, method="PUT", data=data, headers={**headers, "X-CSRF-Token": csrf, "Content-Type": content_type, **(extra or {})})
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        raise SystemExit(f"PUT {path} -> {error.code} {error.read()[:300]}")

FIELDS = [  # name, label, rect (x1, y1, x2, y2)
    ("Name", "Name, Vorname", (200, 740, 520, 760)), ("Personalnummer", "Personalnummer", (200, 710, 520, 730)),
    ("Von", "Urlaub von", (200, 680, 340, 700)), ("Bis", "bis einschließlich", (380, 680, 520, 700)),
    ("Arbeitstage", "Arbeitstage", (200, 650, 340, 670)), ("Resttage", "Resttage nach Antrag", (380, 650, 520, 670)),
    ("Vertreter", "Vertretung", (200, 620, 520, 640)), ("FreiVon", "Freie Tage (von)", (200, 590, 340, 610)), ("FreiBis", "(bis)", (380, 590, 520, 610)),
    ("Datum", "Datum", (200, 540, 340, 560)),
]

def pdf_form():
    objects = {}
    ids = {name: 10 + i for i, (name, _, _) in enumerate(FIELDS)}
    labels = "".join(f"BT /Helv 10 Tf 40 {rect[1] + 6} Td ({label}) Tj ET\n" for _, label, rect in FIELDS)
    content = f"BT /Helv 16 Tf 40 790 Td (Urlaubsantrag \\(synthetisch\\)) Tj ET\n{labels}"
    for name, _, rect in FIELDS:
        objects[ids[name]] = (f"<< /Type /Annot /Subtype /Widget /FT /Tx /T ({name}) /V () /DA (/Helv 10 Tf 0 g) /F 4 /P 3 0 R "
                              f"/Rect [{' '.join(map(str, rect))}] /MK << /BC [0.4 0.4 0.4] >> >>").encode()
    objects[1] = f"<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [{' '.join(f'{i} 0 R' for i in ids.values())}] /DA (/Helv 0 Tf 0 g) /DR << /Font << /Helv 5 0 R >> >> >> >>".encode()
    objects[2] = b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
    objects[3] = (f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /Helv 5 0 R >> >> /Contents 4 0 R "
                  f"/Annots [{' '.join(f'{i} 0 R' for i in ids.values())}] >>").encode()
    objects[4] = b"<< /Length %d >>\nstream\n" % len(content.encode()) + content.encode() + b"\nendstream"
    objects[5] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
    out, offsets = b"%PDF-1.7\n", {}
    for number in sorted(objects):
        offsets[number] = len(out)
        out += f"{number} 0 obj\n".encode() + objects[number] + b"\nendobj\n"
    size = max(objects) + 1
    xref = len(out)
    out += f"xref\n0 {size}\n0000000000 65535 f \n".encode()
    for number in range(1, size):
        out += (f"{offsets[number]:010d} 00000 n \n" if number in offsets else "0000000000 65535 f \n").encode()
    return out + f"trailer\n<< /Size {size} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()

def simple_pdf(text):
    stream = f"BT /F1 20 Tf 60 740 Td ({text}) Tj ET".encode()
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream", b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    out, offsets = b"%PDF-1.4\n", []
    for index, body in enumerate(objs, 1):
        offsets.append(len(out)); out += f"{index} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode() + b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
    return out + f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()

def png(width=320, height=200):
    rows = b"".join(b"\x00" + b"".join(bytes((x * 255 // width, y * 255 // height, 170)) for x in range(width)) for y in range(height))
    chunk = lambda tag, body: struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")

put("/vacation/request-form/file", pdf_form(), "application/pdf", {"X-File-Name": urllib.parse.quote("Urlaubsantrag-synthetisch.pdf")})
mapping = {
    "version": 1, "person": {"lastName": "Beispiel", "firstName": "Alex", "personnelNo": "000815", "department": "Test", "place": "Musterstadt"},
    "dateFormat": "dd.MM.yyyy", "flatten": False, "overlays": [],
    "fields": {
        "Name": {"source": "lastName"}, "Personalnummer": {"source": "personnelNo"}, "Von": {"source": "dateFrom"}, "Bis": {"source": "dateTo"},
        "Arbeitstage": {"source": "workingDays"}, "Resttage": {"source": "restAfter"}, "Vertreter": {"source": "substitute"},
        "FreiVon": {"source": "freeRangeFrom", "index": 1}, "FreiBis": {"source": "freeRangeTo", "index": 1}, "Datum": {"source": "today"},
    },
}
mapping["fields"]["Name"] = {"source": "fullName"}
put("/vacation/request-form/mapping", json.dumps(mapping).encode(), "application/json")

open(os.path.join(outdir, "krankschein.pdf"), "wb").write(simple_pdf("Krankschein (synthetisch)"))
open(os.path.join(outdir, "foto.png"), "wb").write(png())
open(os.path.join(outdir, "gross.txt"), "wb").write(b"x" * (11 * 1024 * 1024))
print("seeded template and sample files in", outdir)
