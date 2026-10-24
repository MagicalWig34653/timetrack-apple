#!/usr/bin/env python3
"""SG1 seed for a THROWAWAY backend (>= contract 0.28.0): seed-throwaway.py plus automation suggestions and cancelled entries.

usage: seed-sg1.py <backend-binary> <workdir> <port>   (port >= 18500, never 18080); prints `TT_DEV_SERVER=... TT_DEV_COOKIE=...`.
Adds: two places in suggestion mode, two open "start" suggestions (20 and 21 days ago), three cancelled entries 28-30 days ago
(one of them overlaps a live entry, so restoring it answers 409 segment_overlap). All data is synthetic.
"""
import datetime as dt, json, os, re, subprocess, sys, urllib.request, uuid
from zoneinfo import ZoneInfo

binary, workdir, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
here = os.path.dirname(os.path.abspath(__file__))
out = subprocess.run([sys.executable, os.path.join(here, "seed-throwaway.py"), binary, workdir, str(port)], capture_output=True, text=True, check=True).stdout
token = re.search(r"TT_DEV_COOKIE=(\S+)", out).group(1)
base = f"http://127.0.0.1:{port}/api/v1"
berlin = ZoneInfo("Europe/Berlin")
today = dt.datetime.now(berlin).date()

def call(method, path, body=None, bearer=None, csrf=None):
    headers = {"Content-Type": "application/json"}
    if bearer: headers["Authorization"] = f"Bearer {bearer}"
    else: headers.update({"Cookie": f"tt_session={token}", "X-CSRF-Token": csrf or ""})
    request = urllib.request.Request(base + path, method=method, data=json.dumps(body).encode() if body is not None else None, headers=headers)
    try:
        with urllib.request.urlopen(request) as response:
            data = response.read()
            return json.loads(data) if data else None
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {path} -> {error.code} {error.read()[:300]}")

csrf = call("GET", "/auth/session").get("csrfToken")
at = lambda day, hhmm: dt.datetime(day.year, day.month, day.day, *map(int, hhmm.split(":")), tzinfo=berlin).isoformat()
ago = lambda days: today - dt.timedelta(days=days)

office = call("POST", "/places", {"name": "Büro", "kind": "office", "automationMode": "suggest", "latitude": 51.48, "longitude": 11.97, "radiusMeters": 120, "confirmAfterSeconds": 0}, csrf=csrf)
client = call("POST", "/places", {"name": "Kunde Nord", "kind": "customer", "automationMode": "suggest", "latitude": 51.52, "longitude": 11.99, "radiusMeters": 120, "confirmAfterSeconds": 0}, csrf=csrf)
device = call("POST", "/me/device-tokens", {"name": "SG1 seed"}, csrf=csrf)["token"]

def event(kind, place, day, hhmm):
    return call("POST", "/automation/events", {"eventId": str(uuid.uuid4()), "deviceId": "sg1-seed", "type": kind, "placeId": place["id"],
                                               "occurredAt": dt.datetime(day.year, day.month, day.day, *map(int, hhmm.split(":")), tzinfo=berlin).astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")}, bearer=device)

for place, days, hhmm in [(office, 20, "09:00"), (client, 21, "08:30")]:
    print(event("arrival", place, ago(days), hhmm), file=sys.stderr)
    print(event("presence_confirmed", place, ago(days), hhmm), file=sys.stderr)

def segment(day, kind, a, b, note=None):
    return call("POST", "/time/segments", {"kind": kind, "startedAt": at(day, a), "endedAt": at(day, b), "note": note}, csrf=csrf)

def cancel(seg, reason):
    request = urllib.request.Request(f"{base}/time/segments/{seg['id']}?reason={urllib.parse.quote(reason)}", method="DELETE",
                                     headers={"Cookie": f"tt_session={token}", "X-CSRF-Token": csrf})
    urllib.request.urlopen(request).read()

import urllib.parse
overlapping = segment(ago(30), "work", "08:00", "12:00", "Doppelt erfasst")
cancel(overlapping, "Versehentlich doppelt angelegt")
segment(ago(30), "work", "09:00", "10:00", "Bleibt bestehen")  # live entry inside the cancelled one: restoring conflicts
cancel(segment(ago(29), "work", "08:00", "12:30", "Falscher Tag"), "Falscher Tag erfasst")
cancel(segment(ago(28), "travel", "07:30", "08:15", "Testfahrt"), "Nur ein Test")
print(f"TT_DEV_SERVER=http://127.0.0.1:{port} TT_DEV_COOKIE={token}")
