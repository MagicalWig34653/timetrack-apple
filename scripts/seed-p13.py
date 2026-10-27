#!/usr/bin/env python3
"""P13 seed for a THROWAWAY backend (>= contract 0.35.0): seed-throwaway.py plus plan days with several plan blocks.

usage: seed-p13.py <backend-binary> <workdir> <port>   (port >= 18500, never 18080); prints `TT_DEV_SERVER=... TT_DEV_COOKIE=...`.
Adds: one place "Büro" and, for the current and the next week, plan days with split blocks (school + work, work + travel + customer).
All data is synthetic.
"""
import datetime as dt, json, os, re, subprocess, sys, urllib.request
from zoneinfo import ZoneInfo

binary, workdir, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
here = os.path.dirname(os.path.abspath(__file__))
out = subprocess.run([sys.executable, os.path.join(here, "seed-throwaway.py"), binary, workdir, str(port)], capture_output=True, text=True, check=True).stdout
token = re.search(r"TT_DEV_COOKIE=(\S+)", out).group(1)
base = f"http://127.0.0.1:{port}/api/v1"
today = dt.datetime.now(ZoneInfo("Europe/Berlin")).date()
monday = today - dt.timedelta(days=today.weekday())

def call(method, path, body=None, csrf=None):
    headers = {"Content-Type": "application/json", "Cookie": f"tt_session={token}", "X-CSRF-Token": csrf or ""}
    request = urllib.request.Request(base + path, method=method, data=json.dumps(body).encode() if body is not None else None, headers=headers)
    try:
        with urllib.request.urlopen(request) as response:
            data = response.read()
            return json.loads(data) if data else None
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {path} -> {error.code} {error.read()[:300]}")

csrf = call("GET", "/auth/session").get("csrfToken")
office = call("POST", "/places", {"name": "Büro", "kind": "office", "automationMode": "off"}, csrf=csrf)
block = lambda s, e, kind, **extra: {"start": s, "end": e, "kind": kind, **extra}
for week in (monday, monday + dt.timedelta(days=7)):
    iso = week.isocalendar()
    days = [
        {"date": week.isoformat(), "mode": "office", "blocks": [block("08:00", "12:00", "school", note="Mathe"), block("13:00", "17:00", "work", placeId=office["id"])]},
        {"date": (week + dt.timedelta(days=1)).isoformat(), "mode": "office",
         "blocks": [block("08:00", "11:30", "office", placeId=office["id"]), block("12:15", "13:00", "travel"), block("13:00", "16:30", "customer", note="Beratung")]},
        {"date": (week + dt.timedelta(days=2)).isoformat(), "mode": "home", "blocks": [block("09:00", "17:30", "home")]},
    ]
    print(call("PUT", f"/plan/weeks/{iso.year}-W{iso.week:02d}", {"replace": False, "days": days}, csrf=csrf) is not None, file=sys.stderr)
print(f"TT_DEV_SERVER=http://127.0.0.1:{port} TT_DEV_COOKIE={token}")
