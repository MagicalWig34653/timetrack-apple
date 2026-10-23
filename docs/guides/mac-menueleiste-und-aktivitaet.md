# Mac: Menüleiste, Automatik und Aktivitätserfassung

Stand: 23.10.2026 (Paket M2). Status: Alpha. Gebaut und per Debug-Bild gesichtet, **nicht am echten Mac im Alltag erprobt**.

## Menüleisten-Begleiter

- **Symbol mit laufender Zeit** (Einstellungen > Menüleiste, abschaltbar). Das Menü zeigt Timer, Tagesstand (Soll/Ist-Balken, Feierabend, Pausenstatus aus derselben Logik wie „Heute“), Schnellstart mit den **drei zuletzt genutzten Arten**, „Fortführen“, „Timetrack öffnen“, Einstellungen, Beenden.
- **Nur Menüleiste**: kein Dock-Symbol, beim Start kein Fenster. Das Menüleisten-Symbol öffnet das Fenster bei Bedarf; solange ein Fenster offen ist, erscheint das Dock-Symbol (sonst lassen sich Fenster und Einstellungen eines „Accessory“-Programms nicht zuverlässig nach vorn holen). Umsetzung: `NSApp.setActivationPolicy`.
- **Beim Anmelden starten**: `SMAppService.mainApp`. Der Zustand wird immer vom System gelesen; verlangt macOS eine Bestätigung, zeigt die Seite einen Link in die Systemeinstellungen.
- **Globales Tastenkürzel** für Start/Stopp (Voreinstellungen ⌃⌥T, ⌃⌥⌘T, ⌃⌥Leertaste, ⌃⌥Return; Standard aus). `RegisterEventHotKey` (öffentliche Carbon-Schnittstelle): keine Berechtigung, keine Mitleserechte für Tastatureingaben; belegte Kürzel meldet die Seite.
- **Hinweise bei laufendem Timer** (Geplantes Ende, 8/10 Stunden, Pause fehlt): derselbe Planer wie auf dem iPhone (OT1, `OverworkPlanner`), nur lokal für diesen Mac. Standard aus, Mitteilungsberechtigung wird erst beim Einschalten erfragt.

## Automatik am Mac (Einstellungen > Automatik)

| Quelle | Stand |
| --- | --- |
| **Orte (CoreLocation)** | Dieselbe Engine wie iOS (Wartezeit, Vorbeifahrt, Abkühlzeit, L4 „Beim Verlassen stoppen“ mit Modus Direkt/Vorschlag). Region-Überwachung mit `CLMonitor`, Berechtigung „Erlaubt“ (auf dem Mac gibt es nur eine Stufe). Auf dem Mac fehlen Significant-Change und Besuche; ausstehende Ankünfte prüft ein Timer im laufenden Programm statt Hintergrundaufgaben. Orte anlegen am aktuellen Standort (ohne Karte). Entitlement `personal-information.location`. |
| **WLAN-Name (SSID)** | **Nicht umgesetzt, bewusst.** CoreWLAN liefert die SSID seit macOS 14 nur mit erteilter Standortberechtigung und im Sandbox-Betrieb zusätzlich mit dem Netzwerk-Entitlement; ob das für die App-Store-Variante zuverlässig freigegeben wird, ist ungeprüft. Zudem wäre „SSID = Ort“ ein schwaches Signal (Heimnetz-Name, Hotspot). Als Ortssignal nur sinnvoll nach Geräteprüfung. |
| **Sperre, Ruhezustand, Inaktivität** | Nur **Fragen, nie automatisch**: „Timer beenden um hh:mm?“ (hh:mm = Moment des Weggehens, nicht der Frage) mit Aktionen Beenden/Weiterlaufen; Schwellen wählbar (Abwesenheit ab 5–60 Min, keine Eingabe seit 5–60 Min). Beim Entsperren/Aufwachen an einem Arbeitsort ohne laufenden Timer: „Timer starten?“ (höchstens einmal pro Stunde, nur nach mindestens 5 Min Abwesenheit, braucht eingeschaltete Standortautomatik). Ein später gestarteter Timer wird nie beendet. Standard aus. Quellen: `NSWorkspace` Sleep/Wake, verteilte Mitteilungen `com.apple.screenIsLocked/Unlocked`, `CGEventSource.secondsSinceLastEventType` (liefert nur eine Zahl, keine Eingaben, keine Berechtigung). |
| **Kalender (EventKit)** | Der iOS-Code (E1/E2: Lesen, Schreiben in den Kalender „Timetrack“, je Kalender Aus/Lesen/Schreiben) läuft jetzt auch am Mac (Einstellungen > Kalender; Entitlement `personal-information.calendars`). |
| Fokus-Filter | Nicht gebraucht (aufgegeben). |

## Aktivitätserfassung (Einstellungen > Aktivität, Seitenleiste „Aktivität“)

**Was sie tut:** Solange ein Timer läuft (Standard) merkt sich Timetrack lokal, welche App im Vordergrund ist (`NSWorkspace.frontmostApplication`: Bundle-ID und Name). Die Ansicht „Aktivität“ zeigt einen Tag als Zeitleiste (Swift Charts, mit den Timer-Einträgen als eigene Spur), eine Tabelle je App (Dauer, Anteil, Regel) und rechts einen Inspector mit den Regeln.

**Opt-in und Datenschutz**
- Alles ist standardmäßig **aus**. Fenstertitel sind ein zweites, getrenntes Opt-in und standardmäßig aus.
- Fenstertitel brauchen die **Bedienungshilfen-Berechtigung** (Datenschutz & Sicherheit). Ohne sie gibt es nur App-Namen. Ehrlicher Hinweis: Ob eine **sandboxed** App (Mac-App-Store-Variante) diese Berechtigung erhalten kann, ist ungeprüft; macOS erlaubt Bedienungshilfen für sandboxed Programme eingeschränkt. Fällt es aus, bleibt die Funktion bei App-Namen, ohne Fehler.
- Kein Tastaturmitschnitt, keine Bildschirmfotos, keine Inhalte. Es werden nur App-Kennung, Name, Start/Ende und (optional) der Titel des fokussierten Fensters gespeichert.
- Nicht erfasst wird bei gesperrtem Bildschirm, Ruhezustand, nach 5 Minuten ohne Eingabe, bei Pause und bei ausgeschlossenen Apps. Abschnitte unter 3 Sekunden (Cmd-Tab) werden verworfen.
- **Pausieren** (Einstellungen, Menüleistenfenster, Menü der Ansicht), **Ausschlussliste je App** (Ausschließen löscht schon gespeicherte Daten dieser App), **Aufbewahrung** 1/7/14/30/90 Tage (Standard 14; Löschen beim Start, stündlich und beim Verkürzen), **„Alle Aktivitätsdaten löschen“**. Das Abschalten der Fenstertitel entfernt bereits gespeicherte Titel.
- Die Daten liegen als JSON im Programmordner der App (`Application Support/Activity`), nicht in der App-Gruppe, nicht in iCloud, **nie am Server**.

**Regeln und Vorschläge**
- Regel: App → Art (optional) und Projekt oder Lernfeld (Text). Daraus entstehen **nur Vorschläge** (Ansicht „Aktivität“, Liste „Vorschläge“): Blöcke ab 5 Minuten innerhalb eines Eintrags (benachbarte Abschnitte gleicher Zuordnung werden zusammengefasst). „Prüfen…“ öffnet ein Blatt mit **bearbeitbarer Notiz** (Label wird an eine vorhandene Notiz angehängt), Art und Korrekturgrund; erst „Übernehmen“ sendet eine normale Korrektur des Eintrags. Verwerfen merkt sich die Entscheidung.
- Die Art wird nur vorgeschlagen, wenn der Block fast den ganzen Eintrag (ab 90 %) deckt. Nichts wird ohne Bestätigung gebucht, nie neue Einträge, nie Zeiten verändert.

## Entitlements und Berechtigungen (Mac)

| Zweck | Eintrag |
| --- | --- |
| Standort | `com.apple.security.personal-information.location`, `NSLocationUsageDescription` |
| Kalender | `com.apple.security.personal-information.calendars`, `NSCalendarsFullAccessUsageDescription` |
| Mitteilungen | zur Laufzeit erfragt (kein Entitlement) |
| Vordergrund-App, Leerlaufzeit, Sperre/Ruhezustand, Hotkey, Anmeldeobjekt | keines nötig |
| Fenstertitel | Bedienungshilfen (Nutzer in Systemeinstellungen), kein Entitlement; Sandbox-Verhalten ungeprüft |

## Grenzen

- Region-Ereignisse, Hintergrundverhalten, Mitteilungsaktionen, Anmeldeobjekt, Hotkey und Bedienungshilfen sind **nur am echten Mac prüfbar** und ungetestet.
- Bei Rechnerstart ohne Anmeldung (Nur-Menüleiste-Modus) wartet die App auf die gespeicherte Sitzung; ohne Netz fehlt der Tagesstand im Menü.
