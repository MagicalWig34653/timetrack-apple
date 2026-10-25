#!/usr/bin/env python3
"""Seed the CX1 automation UI fixture on a throwaway backend.

usage: seed-cx1.py <backend-binary> <workdir> <port>
The backend and account are created by seed-throwaway.py. This script adds the
place expected by AutomationFlowTests; all coordinates and names are synthetic.
"""
import datetime as dt
import json
import pathlib
import re
import subprocess
import sys
import urllib.request
from zoneinfo import ZoneInfo

binary, workdir, port = sys.argv[1:4]
base_seed = pathlib.Path(__file__).with_name("seed-throwaway.py")
result = subprocess.run([sys.executable, str(base_seed), binary, workdir, port], capture_output=True, text=True)
if result.returncode:
    raise SystemExit(result.stderr.strip() or f"base seed failed with status {result.returncode}")
token = re.search(r"TT_DEV_COOKIE=(\S+)", result.stdout).group(1)
base = f"http://127.0.0.1:{port}/api/v1"


def call(method, path, body=None, csrf=None):
    request = urllib.request.Request(
        base + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json", "Cookie": f"tt_session={token}", "X-CSRF-Token": csrf or ""},
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)


csrf = call("GET", "/auth/session")["csrfToken"]
call("POST", "/places", {"name": "Büro Test", "kind": "office", "automationMode": "suggest", "latitude": 51.48,
                            "longitude": 11.97, "radiusMeters": 120, "confirmAfterSeconds": 0}, csrf)
today = dt.datetime.now(ZoneInfo("Europe/Berlin")).date()
last_monday = today - dt.timedelta(days=today.weekday() + 7)
for offset, note in [(0, "Updates ausgerollt"), (2, "Vor-Ort-Termin"), (3, "Lernfeld 5")]:
    day = last_monday + dt.timedelta(days=offset)
    zone = ZoneInfo("Europe/Berlin")
    start = dt.datetime(day.year, day.month, day.day, 18, 0, tzinfo=zone).isoformat()
    end = dt.datetime(day.year, day.month, day.day, 19, 0, tzinfo=zone).isoformat()
    call("POST", "/time/segments", {"kind": "work", "startedAt": start, "endedAt": end, "note": note}, csrf)
print(result.stdout.strip())
