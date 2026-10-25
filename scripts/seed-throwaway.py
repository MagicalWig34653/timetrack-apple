#!/usr/bin/env python3
"""Seeds a THROWAWAY Timetrack backend (SQLite, loopback only) with synthetic data for screenshots.

usage: seed-throwaway.py <backend-binary> <workdir> <port>   (port must be >= 18500, never 18080)
Prints `TT_DEV_SERVER=... TT_DEV_COOKIE=...` and leaves the server running (pid in <workdir>/pid). Delete <workdir> afterwards.
All data is synthetic; the session token is random and only valid for this throwaway database.
"""
import base64, datetime as dt, hashlib, json, os, secrets, shutil, sqlite3, subprocess, sys, time, urllib.request, uuid
from zoneinfo import ZoneInfo

binary, workdir, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
assert port >= 18500 and port != 18080
os.makedirs(workdir, exist_ok=True)
exe = os.path.join(workdir, "App")
shutil.copy(binary, exe)
env = dict(os.environ, SMTP_FROM="noreply@example.test", SQLITE_PATH=os.path.join(workdir, "tt.sqlite"), AUTO_MIGRATE="true",
           PUBLIC_BASE_URL=f"http://localhost:{port}", WEBAUTHN_ORIGIN=f"http://localhost:{port}")
subprocess.run([exe, "bootstrap-admin"], cwd=workdir, env=env, capture_output=True, check=True)

b64 = lambda raw: base64.urlsafe_b64encode(raw).rstrip(b"=").decode()
token = b64(secrets.token_bytes(32))
csrf = b64(hashlib.sha256(("timetrack.csrf.v1:" + token).encode()).digest())
account, now = str(uuid.uuid4()).upper(), time.time()
db = sqlite3.connect(os.path.join(workdir, "tt.sqlite"))
db.execute("insert into accounts (id,handle,display_name,email,role,created_at) values (?,?,?,?,?,?)", (account, "alex", "Alex Beispiel", None, "admin", now))
db.execute("insert into sessions (id,account_id,token_hash,csrf_token_hash,recovery,created_at,expires_at) values (?,?,?,?,?,?,?)",
           (str(uuid.uuid4()).upper(), account, b64(hashlib.sha256(token.encode()).digest()), b64(hashlib.sha256(csrf.encode()).digest()), 0, now, now + 86400 * 30))
# PL1: a second synthetic account that shares its plan and vacation with alex (incoming share), created through its own session.
other, other_token = str(uuid.uuid4()).upper(), b64(secrets.token_bytes(32))
other_csrf = b64(hashlib.sha256(("timetrack.csrf.v1:" + other_token).encode()).digest())
db.execute("insert into accounts (id,handle,display_name,email,role,created_at) values (?,?,?,?,?,?)", (other, "ben", "Ben Beispiel", None, "member", now))
db.execute("insert into sessions (id,account_id,token_hash,csrf_token_hash,recovery,created_at,expires_at) values (?,?,?,?,?,?,?)",
           (str(uuid.uuid4()).upper(), other, b64(hashlib.sha256(other_token.encode()).digest()), b64(hashlib.sha256(other_csrf.encode()).digest()), 0, now, now + 86400 * 30))
db.commit(); db.close()

server = subprocess.Popen([exe, "serve", "--hostname", "127.0.0.1", "--port", str(port)], cwd=workdir, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
open(os.path.join(workdir, "pid"), "w").write(str(server.pid))
base = f"http://127.0.0.1:{port}/api/v1"

def call(method, path, body=None, as_other=False):
    request = urllib.request.Request(base + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                     headers={"Content-Type": "application/json", "Cookie": f"tt_session={other_token if as_other else token}", "X-CSRF-Token": other_csrf if as_other else csrf})
    try:
        with urllib.request.urlopen(request) as response:
            data = response.read()
            return json.loads(data) if data else None
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {path} -> {error.code} {error.read()[:300]}")

for _ in range(60):
    try: urllib.request.urlopen(f"http://127.0.0.1:{port}/api/v1/modules"); break
    except urllib.error.HTTPError: break
    except Exception: time.sleep(0.5)

# Session cookie is accepted; csrf token comes from the session endpoint in the real app. Fetch it so writes work.
session = call("GET", "/auth/session")
if isinstance(session, dict) and session.get("csrfToken"): csrf = session["csrfToken"]

berlin = ZoneInfo("Europe/Berlin")
today = dt.datetime.now(berlin).date()
call("POST", "/work-models", {"validFrom": (today - dt.timedelta(days=today.weekday() + 7)).isoformat(), "timezone": "Europe/Berlin", "weeklyTargetSeconds": 38 * 3600 + 1800,
                              "workdays": [1, 2, 3, 4, 5], "roundingEnabled": True, "roundingMinutes": 15})
call("PUT", "/vacation/settings", {"region": "DE-ST", "annualEntitlementHalfDays": 60, "carryOver": {}, "carryOverExpiry": None}) if False else None

def at(day, hhmm):
    hour, minute = map(int, hhmm.split(":"))
    return dt.datetime(day.year, day.month, day.day, hour, minute, tzinfo=berlin).isoformat()

def seg(day, kind, a, b, note=None):
    call("POST", "/time/segments", {"kind": kind, "startedAt": at(day, a), "endedAt": at(day, b), "note": note})

monday = today - dt.timedelta(days=today.weekday())
plans = {  # weekday offset -> segments
    -7: [("work", "07:55", "12:10", "Wartung Serverraum"), ("work", "12:40", "16:20", None)],
    -6: [("school", "08:00", "15:15", "Berufsschule")],
    -5: [("travel", "07:30", "08:00", None), ("work", "08:00", "12:00", "Kundentermin"), ("work", "12:30", "17:00", None)],
    -4: [("work", "08:05", "12:30", None), ("work", "13:00", "16:45", "Berichtsheft vorbereitet")],
    -3: [("work", "08:00", "13:00", None)],
    0: [("work", "07:58", "12:03", "Updates ausgerollt"), ("work", "12:35", "16:30", None)],
    1: [("school", "08:00", "14:30", "Berufsschule")],
    2: [("travel", "07:40", "08:10", None), ("work", "08:10", "12:15", "Vor-Ort-Termin"), ("work", "12:45", "17:05", "Dokumentation")],
    3: [("work", "08:02", "12:20", None), ("work", "13:00", "16:00", None)],
}
for offset, items in plans.items():
    day = monday + dt.timedelta(days=offset)
    if day < today:
        for item in items: seg(day, *item)
if "--no-today" not in sys.argv:
    for item in [("work", "08:00", "12:15", "Planung Sprint"), ("travel", "12:30", "13:00", None), ("school", "13:30", "16:00", "Lernfeld 5")]:
        seg(today, *item)

year = today.year
nxt = monday + dt.timedelta(days=21)
for kind, start, end, status in [("vacation", nxt, nxt + dt.timedelta(days=4), "approved"), ("sick", monday - dt.timedelta(days=20), monday - dt.timedelta(days=19), "taken"),
                                 ("vacation", monday + dt.timedelta(days=60), monday + dt.timedelta(days=67), "planned"),
                                 ("excused", monday - dt.timedelta(days=40), monday - dt.timedelta(days=40), "taken")]:
    try: call("POST", "/absences", {"kind": kind, "startDate": start.isoformat(), "endDate": end.isoformat(), "status": status})
    except SystemExit as error: print("absence skipped:", error, file=sys.stderr)

try:
    call("POST", "/shares", {"recipientHandle": "alex", "scopes": {"plan": True, "vacation": True}}, as_other=True)
    for offset, mode in [(0, "office"), (1, "home"), (2, "office")]:
        call("PUT", f"/plan/days/{(monday + dt.timedelta(days=offset)).isoformat()}", {"mode": mode, "plannedStart": "08:00", "plannedEnd": "16:30", "plannedBreakMinutes": 30}, as_other=True)
    call("POST", "/absences", {"kind": "vacation", "startDate": (monday + dt.timedelta(days=28)).isoformat(), "endDate": (monday + dt.timedelta(days=32)).isoformat(), "status": "approved"}, as_other=True)
except SystemExit as error: print("share seed skipped:", error, file=sys.stderr)

if "--running" in sys.argv:
    call("POST", "/time/timer/start", {"clientEventId": str(uuid.uuid4()), "kind": "work"})
print(f"TT_DEV_SERVER=http://127.0.0.1:{port} TT_DEV_COOKIE={token}")
