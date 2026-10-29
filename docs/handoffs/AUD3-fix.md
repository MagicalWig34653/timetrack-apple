# AUD3-fix – Korrekturen aus dem Audit AUD3

Branch `aud3-fixes` (von main bc92cad, nicht gemergt, kein Upload, keine Build-Nummer geändert). Ein Commit je Befund (`git log --grep "AUD3-fix"`).

| Befund | Änderung | Test |
| --- | --- | --- |
| 1 Planer-Speichern | `WeekPlanStore.save()` merkt Woche (Epoche) und gesendeten Entwurf vor dem PUT. Antwort wird nur übernommen, wenn dieselbe Woche noch offen ist; Eingaben während des Speicherns bleiben erhalten (Basis wandert, Plan bleibt „ungespeichert“). `open/shiftWeeks` während `isSaving` wird vorgemerkt und nach erfolgreichem Speichern ausgeführt. Nie wird eine Wochen-Antwort in eine andere ISO-Woche geschrieben. | `WeekPlanSaveRaceTests` (2) |
| 2 Jetzt-Leiste | `.dynamicTypeSize(...accessibility1)` und nur Symbole ab Accessibility-Größen (volle `accessibilityLabel` bleiben). | UI-Test `NowBarExtremeTypeTests` (AXXXL; Bild gesichtet, Test selbst übersprungen wegen laufender Seed-Daten nach dem Idle-Bild) |
| 3 Mac Heute | `RootView`: Neuladen bei `NSApplication.didBecomeActiveNotification` und `NSCalendarDayChanged`. | nur Build (kein UI-Test auf Mac) |
| 4 EventKit-Zone | `DeviceCalendarProvider.writtenEvents(..., calendar:)` bekommt die Arbeitsmodell-Zone; Abbildung als `WrittenEvent.reading` im Kern; „Termine entfernen“ nutzt `model.dayCalendar`. | `WrittenEventZoneTests` (2, Berlin gegen Tokio) |
| 5 Kalender-Auto-Sync | `onSaved` des Planers stößt `CalendarAutoSync.request` an (iOS `TimeHub`, Planer-Bildschirm iOS/Mac). | nur Build |
| 6 Tap-Ziele | Pfeile 40 auf 44 pt (`TimeHub`, `CalendarScreen`, `VacationScreen`), Plus-Knopf 32 und Filter-Zurücksetzen 32 auf 44. Die 36-pt-Werte in `WeekZoom`/`MonthPager`/`CalendarScreen` sind nur die gezeichneten Zahlenkreise; die tippbare Zelle ist größer (Spalte bzw. Zeilenhöhe), daher unverändert. | Build |
| 7 Export-Link | „Auswertung und Export“ öffnet `<Server>/export` (PWA-Route `(app)/export`). | Build |
| 9 Wochenwechsel | `WeekStore`: Vorwoche bleibt sichtbar (`isStale`, im UI abgeblendet), Cache von 8 Wochen, Vorabladen der Nachbarwoche in Wischrichtung. `TimeListStore`: gleicher Wochen-Cache. | `WeekStoreStaleTests` (2) |
| 8 Warteschlange | Fehlgeschlagene Rückdatierung wird gemeldet (`DrainResult.correctionFailed`, Meldung in `TodayStore`); Netz-/5xx-Fehler der Korrektur lassen den Eintrag zur Wiederholung stehen. 5xx/429: Backoff 30 s verdoppelnd bis 15 min (`retryNotBefore`), nach 5 Fehlschlägen Eintrag in `attention` (Konfliktblatt, neuer Text `attention.server`), danach laufen die folgenden Einträge. Konten-Zaun unverändert. | `QueueResilienceTests` (5); `WatchStandaloneTests` angepasst (Backoff) |

Nicht umgesetzt (außerhalb): Paritätsfunktionen (Trigger-Links, Konto-Sicherheit); Teile von Befund 8 (`sameKind` verwirft zweites Start still, Push-Token-Wechsel, CancelledStore-Timeouts), Befund 10, `historySuggestion` ohne Cache.

Bekannte Einschränkungen: Ein wiederholter Start nach Netzfehler der Rückdatierung hängt davon ab, dass der Server `clientEventId` idempotent beantwortet (409 `timer_already_running` würde den Eintrag als erledigt verwerfen, die Rückdatierung ginge dann verloren). Gerät und Mac-UI nicht geprüft.
