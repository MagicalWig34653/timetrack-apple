# V5-apple – Wochenansicht: Balken entfernt, Wischen zwischen Wochen

Branch `v5-week-swipe` (Worktree `timetrack-apple-wt/v5`, von `main` 2a94589, Build 52). Nicht gemergt, nicht gepusht, nichts hochgeladen, Build-Nummer unverändert.

## Entfernt
Nutzerrückmeldung: die „komische Leiste mit Balken“ in der Wochenansicht. Das war der Tageszeitstrahl (`PlanTimeline`) aus P13. Entfernt in der Wochenliste (`DayHeader`; die Blöcke stehen dort nur noch als eine Textzeile „08:00–12:00 Schule · 13:00–17:00 Arbeit“), ebenso derselbe Balken in Heute (`UX3Support`, Textzeile bleibt), Kalender-Tagesdetail (`DayDetail`, Blockzeilen bleiben) und „Geteilt mit mir“ (`SharingViews`, Blockzeilen bleiben). **Unverändert:** Blockeditor samt Zeitstrahl im Wochenplaner und Tagesblatt (dort Bearbeitungshilfe), Kalenderabgleich je Block, Planungshinweise, Plan-Ist-Chip, Freigaben, Versions-Gate.

## Wischen
- Zeit-Tab, Zoom Woche: Wischen nach links = nächste Woche, nach rechts = vorige. Die Ansicht folgt dem Finger gedämpft, gleitet beim Wechsel aus, die neue Woche gleitet von der Gegenseite ein; Haptik `selection`. Wechsel über `TimeFocus.shiftWeeks` (wie die Pfeile), Lade-/Cache-Logik unverändert.
- Aktive Bereiche (`weekSwipeArea`): Kopf (Titel/Pfeile), Tagesleiste, Wochenkarte, Tageskopfzeilen. Nicht auf den Eintragszeilen, daher bleiben die Zeilen-Wischaktionen („Als geprüft markieren“, „Stornieren/Bearbeiten“) unberührt. Nur überwiegend horizontale Züge zählen (`WeekSwipe`, Kern, testbar: ≥ 70 pt oder schneller Wisch, Seitenverhältnis 1,6).
- Pfeile, „Heute“, VoiceOver: Tagesleiste hat die Aktionen „Nächste Woche“/„Vorige Woche“; iPad-Tastatur: Befehl + Pfeil links/rechts. Im Planer-Modus und im Monatszoom inaktiv. Bei „Bewegung reduzieren“ kein Gleiten, nur Wechsel.
- Vorabladen der Nachbarwoche nicht gebaut (Stores laden pro Woche; nicht billig ohne Eingriff in `TimeListStore`).

## Prüfung
- Kerntests `swift test --build-system native --no-parallel`: 884 grün (+4 `WeekSwipeTests`).
- Builds unsigniert iOS (Simulator), macOS, watchOS grün.
- UI-Test `Tests/iOSUI/WeekSwipeTests` (iPhone 18 Pro, Wegwerf-Backend mit `scripts/seed-p13.py`): Wischen links ändert den Titel, Wischen rechts zurück, Pfeil und „Heute“ weiter nutzbar: bestanden. Bilder `docs/screenshots/v5-week-no-bar.png` (nachher; vorher: `p13-iphone-week-list.png`), `v5-week-swiped-next.png`.

## Nicht geprüft
Gefühl auf dem Gerät (Dämpfung, Haptik), iPad, Mac (Wischen nur über Trackpad-Gesten der iPad-App; die native Mac-Zeitansicht hat keine Wochenzoom-Oberfläche), VoiceOver-Aktionen nur gebaut, Tastaturkürzel nicht getestet. Wisch-Konflikt mit der System-Zurückgeste nicht relevant (Wurzelansicht). Wischen auf den Zeilen selbst wechselt bewusst nicht die Woche.
