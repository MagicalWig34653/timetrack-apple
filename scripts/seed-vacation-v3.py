#!/usr/bin/env python3
"""V3: adds synthetic absences with all statuses and two attachments to a THROWAWAY backend seeded by seed-throwaway.py.

usage: seed-vacation-v3.py <server-url> <session-token>   (loopback only; all data is synthetic)
"""
import json, struct, sys, urllib.request, uuid, zlib

server, token = sys.argv[1], sys.argv[2]
assert server.startswith("http://127.0.0.1:") or server.startswith("http://localhost:")
base = server + "/api/v1"
headers = {"Cookie": f"tt_session={token}"}

def call(method, path, body=None, raw=None, content_type="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    request = urllib.request.Request(base + path, method=method, data=data, headers={**headers, "X-CSRF-Token": csrf, "Content-Type": content_type})
    try:
        with urllib.request.urlopen(request) as response:
            payload = response.read()
            return json.loads(payload) if payload else None
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {path} -> {error.code} {error.read()[:300]}")

csrf = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/auth/session", headers=headers)).read())["csrfToken"]

def png(width=240, height=160):
    rows = b"".join(b"\x00" + b"".join(bytes((x * 255 // width, y * 255 // height, 170)) for x in range(width)) for y in range(height))
    chunk = lambda tag, body: struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")

def pdf(text):
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

def upload(name, content_type, data):
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{name}\"\r\nContent-Type: {content_type}\r\n\r\n").encode() + data + f"\r\n--{boundary}--\r\n".encode()
    return call("POST", "/files", raw=body, content_type=f"multipart/form-data; boundary={boundary}")

import datetime as dt
today = dt.date.today()
d = lambda days: (today + dt.timedelta(days=days)).isoformat()
made = {}
for key, kind, start, end, status in [
    ("sick-a", "sick", -75, -74, "taken"), ("vac-taken", "vacation", -50, -46, "taken"), ("vac-approved", "vacation", 14, 16, "approved"),
    ("vac-requested", "vacation", 38, 39, "requested"), ("other", "other", 5, 5, "planned"), ("vac-planned-2", "vacation", 50, 52, "planned")]:
    try: made[key] = call("POST", "/absences", {"kind": kind, "startDate": d(start), "endDate": d(end), "status": status})
    except SystemExit as error: print("skipped", key, error, file=sys.stderr)

if "sick-a" in made:
    call("POST", f"/absences/{made['sick-a']['id']}/attachments", {"fileId": upload("Krankschein.pdf", "application/pdf", pdf("Krankschein (synthetisch)"))["id"]})
    call("POST", f"/absences/{made['sick-a']['id']}/attachments", {"fileId": upload("Foto.png", "image/png", png())["id"]})
if "vac-approved" in made:
    call("POST", f"/absences/{made['vac-approved']['id']}/attachments", {"fileId": upload("Urlaubsantrag.pdf", "application/pdf", pdf("Urlaubsantrag (synthetisch)"))["id"]})
print("seeded", sorted(made))
