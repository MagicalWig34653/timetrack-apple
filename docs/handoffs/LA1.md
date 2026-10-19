# Handoff LA1: Live Activity überarbeitet (iPhone und Uhr)

Branch `la1-live-activity`, 19.10.2026. Nicht gemergt, nicht gepusht, keine Build-Erhöhung, kein Upload.

## Umfang
- **Inhalt**: heutige Arbeitszeit als tickende Uhr (`Text(timerInterval:)`, Ursprung = Start minus bereits Erfasstes), Fortschrittsbalken gegen die geplante Tageslänge (`ProgressView(timerInterval:)`, füllt sich ohne Updates), „Feierabend HH:mm“ (geplantes Ende aus dem Plantag, Vertrag 0.17.0 `plannedEnd`), ohne Plan „Soll erreicht ca. HH:mm“ (Schätzung aus dem Soll des Arbeitsmodells, nur laufend), „Soll erreicht“, „von 8:00 geplant“. Planzeiten sind Plan, keine Buchung.
- **Knöpfe**: Pause/Weiter und Stopp als `LiveActivityIntent` (`WidgetPauseTimerIntent`, `WidgetResumeTimerIntent`, `WidgetStopTimerIntent`), Sperrbildschirm, Dynamic Island (expanded), Smart Stack der Uhr (`supplementalActivityFamilies([.small])`, spiegelt die Activity; Intents laufen auf dem iPhone).
- **Pause = normale Pause**: Pause stoppt das laufende Segment (Lücke bleibt echte Pause, nichts erfunden); Weiter startet ein neues Segment derselben Art. Der Server kennt nur „kein Timer“; ein Pausenmarker (`PauseMarker`, App Group, max. 4 h) merkt Art und Pausenbeginn, damit die Activity als „Pausiert“ stehen bleibt. Läuft wieder ein Timer (auch im Web), wird der Marker verworfen; Stopp in der Pause beendet nur die Pause (kein Server-Aufruf).
- **Warteschlange**: Druck wird sofort angewendet (Snapshot, Marker, Activity) und in dieselbe `TimerActionQueue`-Datei wie der Fokus-Filter eingereiht (`TimerControlRunner.queue`, `FocusEnvironment.queue` zeigt darauf), danach sofort zugestellt; offline stellen Start der App, Vordergrund und Hintergrundaufgabe zu, rückdatiert auf den Druckzeitpunkt. `WidgetPublisher.refresh` veröffentlicht nichts, solange die Warteschlange nicht leer ist (sonst überschriebe die alte Serverantwort den optimistischen Zustand).
- **F4 bleibt**: Reconciler (`plan(desired:existing:)`) unverändert in der Logik; Ziel (`LiveActivityTarget`) ist jetzt der Inhaltszustand (Art, Start, Pause, Erfasstes, Plan, Akzent). Lauf ↔ Pause ist `update` (im Hintergrund erlaubt), keine Neuanforderung; `sameTimer` trennt Lauf und Pause.
- **Plan-Quelle**: `WidgetPublisher.attachPlan` liest `GET /plan/days` für heute (App-Sync und Intents); bei Lesefehler bleibt der Plan des Snapshots vom selben Tag. Snapshot-Felder `plannedEnd`, `plannedSeconds` (optional, ältere Snapshots dekodieren). `PlanDay` um `plannedStart/End/BreakMinutes/Seconds` erweitert (optional).
- **Gestaltung**: Akzent des Kontos (Fortschritt, Pause-Knopf, Keyline), hell/dunkel, einzeilig mit `minimumScaleFactor`, Kompakt: Symbol + Uhr (Ring im Kompaktslot verworfen: tickende Kreis-Anzeige erscheint dort nicht), Minimal: Symbol, Expanded: Kopf, Balken, Ende/Länge, zwei Knöpfe.

## Prüfung
- `swift test --build-system native` (TimetrackCore): **307 Tests bestanden** (vorher 279; +28 in `LiveActivityPauseTests`: Zielzustand, Marker-Ablauf, Fortschritt/Klammern/Pause, geplantes Ende vs. Schätzung, Plantag, Dekodierung alt/neu, Knopf-Pläne Pause/Weiter/Stopp/Ignoriertes, gemeinsame Warteschlange, Reconciler bei Pause/Weiter).
- Builds unsigniert: TimetrackIOS (inkl. Widget-Erweiterung), TimetrackWatch, TimetrackMac: BUILD SUCCEEDED.
- Sichtprüfung im Simulator (iPhone 18 Pro, Debug-Galerie `TT_DEV_WIDGET_GALLERY=running-live`, `TT_DEV_LA_PAUSED=1`, `TT_DEV_LA_NOPLAN=1`, `TT_DEV_LA_ACCENT=#D946EF`): `docs/screenshots/la1-running.png`, `la1-paused.png`, `la1-accent.png`; Banner, kompakt, expanded, minimal, Uhr-Layout; Text nirgends abgeschnitten. Näherung, nicht die echte Dynamic Island. Variante ohne Plan nur gebaut, nicht angesehen.
- Nicht geprüft: Intents gegen Server, Warteschlange offline (Logik nur Kerntests), echte Activity.

## Checkliste auf dem Gerät
1. Live Activities erlaubt. Timer starten: Banner mit Uhr, Balken, „Feierabend …“ (Plantag mit Zeiten anlegen; ohne Plan „Soll erreicht ca. …“).
2. Uhr tickt und Balken füllt sich bei gesperrtem Gerät ohne App.
3. Pause auf dem Sperrbildschirm: Activity zeigt „Pausiert“, Uhr steht; Zeit-Tab: Segment endet zur Druckzeit, danach Lücke. Weiter: neues Segment derselben Art.
4. Stopp (laufend und pausiert): Activity verschwindet; bei Pause kein neues Segment.
5. Dynamic Island: kompakt, minimal (mit zweiter App), lange drücken: expanded, Knöpfe funktionieren.
6. Flugmodus: Pause, Weiter, Stopp drücken; Activity reagiert sofort; Netz zurück, App öffnen: Segmente mit Druckzeiten, nichts doppelt.
7. Uhr: Smart Stack zeigt die gespiegelte Activity; Pause/Stopp dort wirken. (Unklar, ob die Uhr sie ohne offene Uhr-App zeigt.)
8. Timer im Web starten/stoppen: Activity folgt beim Öffnen der App (kein Push, wie bisher).
9. Akzent wechseln, hell/dunkel, größte Schrift: nichts abgeschnitten.
10. Pause 4 h+ stehen lassen: Marker läuft ab, Activity endet beim nächsten Abgleich (App öffnen).

## Offen
- Geplantes Ende wird in der Gerätezeitzone formatiert (Arbeitsmodell-Zone nicht im Zustand).
- Die Uhr-Layouts sind unverifiziert; ob die Uhr-Intents tatsächlich auf dem iPhone ohne Erreichbarkeit laufen, nur am Gerät klärbar.
- Eigenständige Uhr-App (A12) hat weiter keine Pause; nur die gespiegelte Activity.
