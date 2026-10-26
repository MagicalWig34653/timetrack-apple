# Handoff N2-apple: dunkle Live-Activity-Karte, Kalender-Abgleich (EventKit)

Branch `n2-la-dark-calendar-sync` (von `main` 7b20807), 26.10.2026. Nicht gemergt, nicht gepusht, keine Build-Erhöhung, kein Upload.

## 1. Live Activity / Smart Stack zu hell
Ursache: Die „Dezent“-Tönung (Q1) war mit Helligkeit 0,19 bei Alpha 0,94 praktisch deckend; auf der Uhr wirkt das als helle graue Karte.
- `LiveActivityTint.color(.subtle, dark)` (Kern, gleiche Funktion für iPhone-Sperrbildschirm und Uhr): Helligkeit 0,10, Alpha 0,5, Sättigung 0,4 x Akzent (max. 0,5), Farbton bleibt je Art/Konto erhalten. „Grau“: Helligkeit 0,08, Alpha 0,5. „Farbig“ und die helle Variante unverändert. Die iOS-Tönung ist damit dieselbe Funktion, also konsistent.
- Tests: `subtleDarkIsAlmostTransparentButReadable` (Alpha <= 0,55, Helligkeit <= 0,12, Weiß-Kontrast >= 7 über Grau 0,34 und >= 4,5 über Grau 0,62); bestehende Kontrasttests grün.
- Bild: `docs/screenshots/n2-watch-dark.png` (Galerie der Smart-Stack-Karten im iPhone-Simulator, dunkel; Untergrund der Näherung ist Grau 0,34).
- Nicht geprüft: echtes Smart-Stack-Rendering auf der Uhr (Systemmaterial, wie stark die Karte durchscheint, Always-On), Sperrbildschirm am iPhone. Falls zu transparent/zu dunkel: nur Alpha/Helligkeit in `LiveActivityTint.swift` ändern.

## 2. Kalender-Abgleich (EventKit)
Befund (E1/E2): Der Abgleich lief nur aus `CalendarScreen`/`TimeHub` und nur für das sichtbare Monatsraster. Verkürzter, verschobener, stornierter oder gelöschter Urlaub außerhalb des geöffneten Monats blieb im Kalender stehen; ohne Merkzettel war ein von Hand gelöschter Termin nicht von „noch nie geschrieben“ unterscheidbar und wurde beim nächsten Lauf wieder angelegt; die Termin-Kennung wurde nie gespeichert; die Marker-URL allein ging verloren, wenn ein Server das URL-Feld verwarf.
Neu:
- **Ledger** (`CalendarLedger`, je Gerät in `UserDefaults`, nie zum Backend): je Kalender Schlüssel (`absence/<uuid>`, `plan/<Tag>`) -> Termin-Kennung, Titel, Tage. Die Marker auf den Terminen bleiben die Quelle der Wahrheit; der Ledger ist nur Gedächtnis.
- **`CalendarReconciler`** (Kern, rein): erzeugt/ändert/löscht je Schlüssel; Duplikate weg (der im Ledger bekannte gewinnt); Ereignisse außerhalb des Fensters, andere Schlüsselfamilien und Termine ohne Marker werden nie angefasst. Von Hand gelöschter Termin: bleibt gelöscht, solange der Eintrag auf dem Server unverändert ist (Ledger-Inhalt = Soll), wird bei Änderung wieder geschrieben. Geänderte EKEvent-Kennung: Termin wird über den Marker gefunden, Update statt Duplikat, Ledger wird repariert. Verlorener Ledger (Neuinstallation): eigene Termine werden über den Marker im Fenster gefunden und abgeglichen (kein Duplikat; ein von Hand gelöschter Termin wird dann einmalig neu geschrieben, weil das Wissen fehlt).
- **`DeviceCalendarStore.syncAll(source:)`**: liest Abwesenheiten selbst vom Server (Fenster -366/+731 Tage, unabhängig vom offenen Monat) und bei aktivem Plan-Schalter Plantage (-31/+120 Tage), dann Abgleich je Schreib-Kalender. Lesefehler = nichts ändern (kein Löschen bei Netzfehler). Parallele Aufrufe werden zu genau einem Folgelauf zusammengefasst.
- **Auslöser** (`Sources/Calendar/CalendarAutoSync.swift`, iOS und Mac): Start, App aktiv, Anmeldung, jede Änderung an Abwesenheiten (Urlaubsplaner und Kalender-Store), Plantagen und Kalender-Einstellungen; 0,8 s entprellt. Die alten Abgleich-Aufrufe in `CalendarScreen`/`TimeHub` (nur sichtbares Raster) entfallen; `sync(...)` bleibt als API (Tests, Demo).
- **EventKitProvider**: `apply` gibt die Kennungen nach dem Commit zurück; Marker zusätzlich in den Notizen (`timetrack://…` plus kurzer Hinweis, keine Nutzerdaten), gelesen wird aus URL oder Notizen. Nur Termine mit Marker im Schreib-Kalender werden geändert/gelöscht.
- Zurückstellen eines Kalenders auf Lesen/Aus und „Von Timetrack geschriebene Termine entfernen“ leeren den Ledger.
- Alte Termine aus E2 ohne Notiz-Marker werden über die URL erkannt und beim nächsten Update um die Notiz ergänzt.

## Prüfung
- `swift test --build-system native --no-parallel` (TimetrackCore): **796 Tests bestanden** (neu: 1 Tint, 16 Abgleich).
- Unsignierte Builds TimetrackIOS (Simulator), TimetrackMac, TimetrackWatch: BUILD SUCCEEDED (xcodegen neu erzeugt, `CalendarAutoSync.swift` im Mac-Ziel).
- Kein UI-Test für den Abgleich neu geschrieben; E2-UI-Tests nicht erneut gelaufen.

## Nicht geprüft (Gerät)
- Echtes EventKit: Kennungswechsel bei iCloud/Exchange-Sync, ob Notizen/URL auf allen Servern erhalten bleiben, mehrtägige ganztägige Termine, von Hand gelöschte Termine (Gerät sieht Löschung über anderen Gerät erst nach Sync).
- Hintergrundlauf: der Abgleich läuft nur bei geöffneter App (Start, aktiv, Änderung), nicht im Hintergrund.
- Plan-Fenster -31/+120 Tage: ältere/fernere Plantage werden nicht geschrieben und nicht bereinigt.

## Offene Fragen
1. Reicht das Absenzfenster (1 Jahr zurück, 2 Jahre voraus)? 2. Soll der Hintergrundabgleich (BGAppRefreshTask) folgen?
