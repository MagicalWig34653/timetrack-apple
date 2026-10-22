# H1b – Heute: ein Start/Stopp-Element, Abfahrt per Kurzbefehl stoppt jeden Timer

Branch `h1-today-start` (Worktree `timetrack-apple-wt/h1`). Nicht gemergt, nicht gepusht, Build-Nummer unverändert, kein Upload. Der Name „H1b“ vermeidet die Kollision mit dem Haptik-Paket H1 (`docs/handoffs/H1.md`).

## 1. Heute: doppelter Start/Stopp
Befund: Seit UX3 boten die Jetzt-Leiste (`tabViewBottomAccessory`) und die Timer-Karte auf Heute beide Start/Stopp. Die Karte hat bereits ein 54-pt-Ziel (`.controlSize(.large)`, `ttPrimary`/`ttDanger`); zu wenig Rand hatte die **Jetzt-Leiste**: Kapsel „Starten“ und runder Stopp lagen am Rand der Leiste an.
Entscheidung: Regel „Leiste auf allen Tabs außer Heute, auf Heute die Karte“. Einfacher als umgekehrt (Karte trägt Artenwahl, Uhr, Kontext), und die Leiste verdeckte auf Heute das Listenende.
- `RootView.swift`: `.tabViewBottomAccessory(isEnabled: model.today != nil && ui.selection != .today)`.
- `NowBar.swift`: Innenrand (horizontal `l`, vertikal `xs`), Ziele bleiben ≥ 44 pt.
- iPad/Mac: unverändert (Seitenleisten-Fußzeile zeigt nur die Uhr, die Karte ist das einzige Element); nicht neu gesichtet.
- UI-Test `NowBarTests.testStartAndStopFromAnotherTab` angepasst (auf Heute keine Leisten-Knöpfe, Karte ≥ 44 pt, Leiste auf anderem Tab wieder da): grün auf iPhone-18-Pro-Simulator.
- Bilder: `docs/screenshots/h1-nowbar-idle.png`, `h1-today-idle.png`, `h1-today-running.png` (verkleinert).

## 2. Abfahrt per Kurzbefehl
Befund: L4 (Region-Verlassen) stoppt bereits handgestartete Timer, aber nach 3 min Wartezeit und Standortprüfung beim nächsten Weckruf. Der Kurzbefehl „Abfahrt erfassen“ lief durch dieselbe Warteschlange; die Antwort lautete „Für X war keine Ankunft erfasst“, das Protokoll „Ignoriert: keine Ankunft vorgemerkt“, und ohne späteren Weckruf wurde nichts gestoppt.
Änderung (Kern, rein clientseitig, kein Backend nötig; stoppt weiter über `TimerActionQueue`):
- `AutomationEngine.shortcutLeft`: Abfahrt wird als eindeutiger Beleg behandelt, kein Warten, keine Standortprüfung; der Timer wird sofort beobachtet und gestoppt (Direkt, Endzeit = Meldezeitpunkt), angeboten (Vorschlag) oder in Ruhe gelassen (Aus, Schalter „Beim Verlassen stoppen“ aus, Automatik global aus). Kein Timer: nichts. Timer nach der Abfahrt gestartet: nicht gestoppt. Timerzustand unlesbar: Abfahrt bleibt vorgemerkt, nächster Weckruf erledigt sie. Doppelte Stopps verhindert die stabile Event-Id.
- `LeaveStopFilter.schedule(explicit:)`: bei Kurzbefehl greifen die Vorbeifahrt-Heuristiken (kurzer Aufenthalt, Abfahrt vor Fälligkeit der Ankunft) nicht.
- Texte: Kurzbefehl-Antworten für alle Ausgänge, Protokolltext „Kein Besuch vorgemerkt, nichts an den Server gemeldet (ein laufender Timer wird trotzdem geprüft)“; Anleitung `docs/guides/standortautomatik.md`.
- Region-Verlassen unverändert (3 min Wartezeit, Standortprüfung), weil dort ein Signal ungenau sein kann.
- Neu `ShortcutLeaveStopTests` (13 Tests, u. a. Handstart dann Verlassen, kein Timer, Vorschlag, Aus, Schalter aus, global aus, Neustart danach, offline, unbekannter Zustand, Doppelaufruf, ohne Plattformaktionen).

## Prüfung
- `swift test --build-system native` TimetrackCore: 519 Tests grün (Stand davor 506).
- Builds iOS (via UI-Test), macOS, watchOS: grün (unsigniert).

## Offen
- Große Dynamic-Type-Stufen und iPad nicht neu gesichtet; Leiste/Karte auf Gerät ungeprüft.
- Das parallele Backend-Paket W1 (Server-`departure` beendet Handtimer) ist unabhängig; ein doppelter Stopp ist harmlos (409 `no_running_timer` zählt als erledigt).
- Echter Kurzbefehl am Gerät ungeprüft.
