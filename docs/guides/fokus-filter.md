# Fokus-Filter: Timer mit einem iOS-Fokus verbinden

## Was ist das?
Mit einem Fokus (zum Beispiel „Arbeit“) stellt iOS Mitteilungen und Apps auf einen Zweck ein. Der Fokus-Filter von Timetrack verbindet diesen Fokus mit dem Timer: Schaltest du den Fokus ein, startet Timetrack den Timer oder fragt vorher nach. Endet der Fokus, stoppt Timetrack den Timer wieder – wieder auf Wunsch mit Rückfrage.

Der Filter erscheint nur, wenn das Modul „Automatik“ in deinem Konto und auf dem Server eingeschaltet ist. In der App findest du die Erklärung unter Einstellungen › Fokus-Filter.

## Einrichten in drei Schritten
1. iOS-Einstellungen öffnen › **Fokus** › deinen Fokus wählen (zum Beispiel „Arbeit“).
2. Unter **Fokusfilter** auf **Filter hinzufügen** tippen und **Timetrack** wählen.
3. Auswählen, **was Timetrack tun soll** und **welche Art** gebucht wird (Arbeit, Fahrt oder Schule). Optional: einen Ort und einen Namen für die Mitteilungen. **Hinzufügen** tippen.

Pfad zum Merken: *Einstellungen › Fokus › [dein Fokus] › Fokusfilter › Timetrack*

Damit Rückfragen ankommen, erlaube Mitteilungen für Timetrack (Einstellungen › Fokus-Filter in der App zeigt den Stand) und nimm Timetrack in die „Erlaubten Apps“ deines Fokus auf. Sonst hält iOS die Rückfrage zurück, bis der Fokus vorbei ist.

## Die drei Möglichkeiten
- **Nachfragen** (zum Ausprobieren empfohlen): Beim Einschalten kommt die Mitteilung „Timer starten?“ mit **Start** und **Nicht jetzt**, beim Ende „Timer stoppen?“ mit **Stopp** und **Weiterlaufen lassen**. Es gibt keine Rückfrage, wenn nichts zu tun wäre (läuft schon ein Timer derselben Art, oder es läuft keiner).
- **Automatisch starten und stoppen**: Ohne Rückfrage. Läuft schon ein Timer, bleibt er unberührt.
- **Nichts tun**: Timetrack merkt sich nur, dass der Fokus an ist.

## Sicherheitsregeln
- Beim Ende des Fokus stoppt Timetrack nur Timer, die der Fokus selbst gestartet hat. Von Hand gestartete Timer laufen weiter, außer du schaltest „Auch von Hand gestartete Timer beenden“ ein.
- Ein Timer anderer Art (zum Beispiel Fahrt statt Arbeit) wird nie gestoppt.
- Timetrack erfindet keine Pausen oder Lücken.
- Ohne Anmeldung bucht der Filter nichts; es kommt ein Hinweis, dich anzumelden.

## Ausprobieren, ohne den Fokus zu wechseln
Auf der Seite „Fokus-Filter“ gibt es den Bereich „Ausprobieren“: Modus und Art wählen, **Fokus an** oder **Fokus aus** tippen. Standardmäßig siehst du nur, was passieren würde. Mit „Wirklich ausführen“ wird tatsächlich gestartet, gestoppt oder eine Mitteilung gesendet. Darunter stehen die letzten zehn Aktionen mit Uhrzeit, den von iOS erhaltenen Angaben und dem Ergebnis.

## Prüfen, was iOS gemeldet hat
Der Bereich „Letzte Meldung von iOS“ zeigt, wann iOS Timetrack zuletzt aufgerufen hat, mit welchen Angaben und was daraus wurde. „Keine Angaben“ heißt: iOS meldet das Ende eines Fokus. Kann der Server gerade nicht erreicht werden, wartet die Aktion (Start oder Stopp) und wird automatisch erneut gesendet (beim Öffnen der App, im Hintergrund oder mit „Wartende Aktionen jetzt senden“). „Diagnose teilen“ erzeugt einen Text ohne Zugangsdaten, den du weitergeben kannst. Steht der Fokus als aktiv, obwohl er aus ist, hilft „Gespeicherten Fokus-Zustand zurücksetzen“.

## Datenschutz
Der Filter speichert nur Modus, Art, Ort und den Zustand „Fokus an/aus“ auf diesem Gerät (App-Gruppe). Zugangsdaten bleiben im Schlüsselbund; der Fokus selbst (Name, Status) wird von iOS nicht an Timetrack verraten, nur dass ein Fokus mit Filter ein- oder ausgeht.

## Fehlersuche
- **Nichts passiert**: Ist der Filter im Fokus hinzugefügt und der Modus nicht leer? Steht auf der Seite „Kein Fokus-Filter aktiv“, obwohl der Fokus an ist, den Filter im Fokus einmal öffnen und mit „Fertig“ bestätigen.
- **Keine Rückfrage**: Mitteilungen für Timetrack erlaubt? Timetrack in den „Erlaubten Apps“ des Fokus?
- **„Bitte in Timetrack anmelden“**: App öffnen und anmelden. (Ist nur der Server nicht erreichbar, erscheint stattdessen „wartet und wird erneut versucht“.)
- **Seite zeigt „Noch keine Meldung von iOS“**: iOS hat Timetrack gar nicht aufgerufen. Filter im Fokus prüfen, Modus wählen, „Fertig“ tippen; Fokus einmal aus- und einschalten.
- **Timer wurde nicht gestoppt**: Er wurde von Hand oder mit anderer Art gestartet (siehe Sicherheitsregeln).
