# Handoff LA2: Live Activity gestalterisch und fachlich überarbeitet, Absturzsuche

Branch `la2-live-activity` (von `main`, Build 12), 19.10.2026. Nicht gemergt, nicht gepusht, keine Build-Erhöhung, kein Upload.

## Ursachen (Screenshots Sperrbildschirm und Smart Stack)
- **Uhr und Balken zu hoch (10:01 statt ca. 5 h)**: Der Server wertet ein offenes Segment bis „jetzt“ aus (`endedAt ?? now`), `evaluatedWorkSeconds` enthält also das laufende Segment bereits. Der Snapshot nahm den Wert als „Erledigtes ohne laufendes Segment“, die Activity addierte das laufende Segment ein zweites Mal. Korrektur: `WidgetSnapshot.finishedSeconds` zieht das laufende Segment bis zum Ladezeitpunkt ab (App: `lastLoaded`, Intent/Uhr: Ladezeit), Clamp auf >= 0. Wirkt auch auf Widgets und Komplikation (gleiche Quelle).
- **Balken**: war Arbeitszeit gegen geplante Länge (Plan ohne Pause = 10:45 h, daher nahezu voll). Jetzt erster Beginn des Tages bis geplantes Ende (`firstStart` im Snapshot, `dayStart` im Zustand); der Balken läuft auch in der Pause weiter (Feierabend rückt näher). Ohne geplantes Ende Rückfall auf Arbeitszeit gegen Plan. Beschriftung „Beginn 8:15“ links, „Feierabend 19:00“ rechts; „von 10:45 geplant“ entfällt.
- **Knöpfe fehlten auf dem Sperrbildschirm**: Platz war reserviert, aber nichts gezeichnet. Wahrscheinliche Ursache (am Gerät nicht verifizierbar): `glassEffect` (E2) auf den Knöpfen rendert in der Live Activity nicht. Jetzt deckende Füllungen (Akzent, Stopp rot), Beschriftung per Theme-Kontrast.
- Leerraum/Unausgewogenheit: neues Layout, eine Kopfzeile (Symbol, Art/Status, große Uhr, runde Pause/Weiter- und Stopp-Knöpfe), darunter Balken mit Beschriftung, Höhe ca. 120 pt (< 160 pt). Große Schriften: `ViewThatFits` stapelt die Knöpfe als beschriftete Kapseln unter die Uhr. Hintergrund mit leichtem Akzent-Ton.
- Dynamic Island expanded: Bereiche leading (Symbol, Status), trailing (Uhr), bottom (Balken, Beschriftung, Pause/Stopp). Kompakt/minimal unverändert.
- **Smart Stack (Uhr)**: Innenabstand 12/10 pt, Knöpfe `.buttonStyle(.glass)` (Liquid Glass), größere Schrift und Trefferfläche. Nur als Näherung in der Debug-Galerie gesichtet (`docs/screenshots/la2-watch-small-*.png`); echtes Smart-Stack-Rendering und ob Glas dort sichtbar ist, nur am Gerät klärbar.

## Absturzsuche (höchste Priorität)
Auf diesem Mac liegen nur macOS-Berichte (DiagnosticReports), keine iOS-Geräteberichte der Live Activity. Code-Review und Stresstest ergaben:
- Potenzielle Traps behoben: negativer `workedSeconds` kehrte den Bereich von `Text(timerInterval:)` (Pause) um, `Int(Double)` bei NaN/unendlich (`wholeSeconds`), Überlauf bei absurden Werten (Clamp 1e9). Bereiche kommen jetzt aus `LiveActivityTarget.clock` und `progressInterval` (immer Beginn < Ende), Division nur bei Nenner > 0.
- Keine Force-Unwraps im Live-Activity-Pfad; `Activity.request` wirft nur (abgefangen); `SerialGate` serialisiert (Test mit 200 gleichzeitigen Läufen: nie zwei gleichzeitig); Abgleich idempotent (Test über alle Kombinationen).
- Stresstest: 5000 zufällige Start/Pause/Weiter/Stopp-Folgen (auch gleichzeitig und mit rückwärts laufender Uhr) halten den Zustand zeichenbar und konsistent.
- Nicht reproduziert, keine bestätigte Absturzursache auf dem Gerät. Die doppelte Zählung vergrößerte Werte, war aber kein Trap. Falls Abstürze bleiben: Geräteabsturzbericht (Einstellungen > Datenschutz > Analyse) bzw. Xcode Organizer nötig.
- **Fund außerhalb von LA** (`~/Library/Logs/DiagnosticReports/Timetrack-2026-10-19-123821.ips`, macOS 27.0.1, Build 8): SIGSEGV in `W.s` (`Sources/Week/WeekSupport.swift:11`) aus `VacationPlannerView.swift:188` (`String(format:)` mit `%d` und `%@`-Argument `weekDecimal(...)`, ein Swift-String als CVarArg). Nicht behoben (anderes Paket); Vorschlag: Zahlen vorab zu String formatieren und nur `%@` verwenden. Die älteren Berichte (17./18.10.) sind SIGABRT durch NSException auf macOS.

## Prüfung
- `swift test --build-system native` (TimetrackCore): **380 Tests bestanden** (vorher 307 laut LA1; +10 `LiveActivityProgressTests`, +6 `LiveActivityRobustnessTests`, ein angepasster Test `makeBuildsFromDayAccountAndSegments` auf die neue Semantik).
- Builds unsigniert: TimetrackIOS (inkl. Widget-Erweiterung) und TimetrackWatch: BUILD SUCCEEDED. Mac nicht neu gebaut (Kern unverändert kompatibel).
- Sichtprüfung Debug-Galerie, iPhone 18 Pro: `docs/screenshots/la2-running.png`, `la2-paused.png`, `la2-watch-small-running.png`, `la2-watch-small-paused.png`. Nicht geprüft: echte Activity, Dynamic Island, Smart Stack, Hell/Dunkel-Sperrbildschirm, größte Schrift.

## Offen
- Auf dem Gerät: Knöpfe sichtbar? Uhr korrekt (ca. Echtzeit seit Beginn)? Balken bei 19:00 Feierabend plausibel? Smart Stack Padding/Glas?
- `TodayDisplay.applying(.stop)` addiert die laufende Zeit auf `doneSeconds` aus Live-Daten (enthält sie schon): gleiche Doppelzählung in der Uhr-Anzeige nach Offline-Stopp, nicht angefasst.
- Geplantes Ende/Beginn in Gerätezeitzone.
