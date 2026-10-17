# Standortautomatik und Kurzbefehle (iPhone und iPad)

Stand: 17.10.2026. Status: Alpha. Die Funktion ist in der Simulation geprüft, aber noch nicht auf einem echten Gerät erprobt.

## Was sie macht

Timetrack kann merken, wenn du einen deiner Orte (zum Beispiel „Büro“) betrittst oder verlässt, und daraus eine Buchung oder einen Vorschlag machen. Ein Standortsignal ist dabei nie dasselbe wie gearbeitete Zeit: Die App meldet nur „angekommen“ und „abgefahren“. Was daraus wird, bestimmt der Modus des Ortes:

| Modus | Ergebnis nach bestätigtem Aufenthalt |
| --- | --- |
| Aus | nichts |
| Vorschlag | ein Vorschlag, den du annimmst oder verwirfst |
| Direkt | ein Eintrag, zurückdatiert auf die Ankunft |

Es gibt zwei Wege, die dieselben Regeln nutzen:

1. **In der App** (Einstellungen, Standortautomatik): iOS überwacht deine Orte und weckt die App beim Betreten oder Verlassen.
2. **Über Kurzbefehle**: Die Kurzbefehle-App löst bei „Ankunft“ oder „Verlassen“ eine Aktion von Timetrack aus.

## Vorbeifahrt wird nicht gebucht

Eine Ankunft wird zuerst nur vorgemerkt. Erst wenn du nach der **Wartezeit** (Standard 4 Minuten, einstellbar von 2 bis 15; mindestens die Bestätigungszeit des Ortes) noch am Ort bist und dich nicht schnell bewegst, wird sie gemeldet. Wer nur vorbeifährt, verlässt den Ort vor Ablauf der Wartezeit: Es entsteht nichts. Nach einer Abfahrt ignoriert die App eine erneute Ankunft am selben Ort für die **Abkühlzeit** (Standard 10 Minuten, bis 60), damit ungenaue Ortung am Rand keine Doppelbuchung auslöst. Pausen werden nie erfunden.

## Einrichten

1. Einstellungen, **Standortautomatik** öffnen und den Schalter einschalten.
2. Orte mit Koordinaten brauchen die App oder die Web-App; in der App geht es mit **Ort am aktuellen Standort anlegen** (Karte mit Radiusvorschau). Der Radius sollte mindestens 100 Meter betragen, kleinere Radien erkennt iOS nicht zuverlässig.
3. Pro Ort **Aus, Vorschlag oder Direkt** wählen. Beginne mit „Vorschlag“: Dort kann nichts Falsches gebucht werden.
4. Standortzugriff erlauben: erst „Beim Verwenden“, dann **„Immer“** und **Genauer Standort**. Ohne „Immer“ kann iOS die App im Hintergrund nicht wecken.

iOS überwacht höchstens 20 Orte gleichzeitig. Hast du mehr aktive Orte, überwacht die App die nächstgelegenen und wählt neu, wenn du dich weit bewegst; die Seite zeigt dir das an.

## Datenschutz

- Dein Standort verlässt das Gerät **nicht**. Gesendet werden nur Ort-ID, Art des Ereignisses (Ankunft, Aufenthalt bestätigt, Abfahrt) und Uhrzeit, keine Koordinaten.
- Gesendet wird mit einem eigenen **Gerätetoken**, das nur Ereignisse melden darf (kein Lesen, kein Ändern). Es liegt im Schlüsselbund und wird nie angezeigt. Unter „Gerätetoken“ kannst du es neu erzeugen oder widerrufen.
- Alle Ereignisse siehst du unter **Protokoll** (die letzten 20, mit Entscheidung und Ergebnis).
- Beim Abmelden werden gemerkte Orte, wartende Ereignisse und das lokale Token gelöscht. Das Token auf dem Server widerrufst du dort unter Geräte.

## Akku

Die App fragt den Standort **nicht laufend** ab. iOS überwacht die Orte selbst mit sehr wenig Energie und weckt die App nur beim Betreten oder Verlassen, bei größeren Ortswechseln und bei längeren Aufenthalten. Eine genaue Ortung läuft nur einmalig, wenn eine Ankunft nach der Wartezeit geprüft wird. So prüfst du den Verbrauch: Einstellungen, Batterie, Timetrack (Hintergrundaktivität).

## Kurzbefehle einrichten

Timetrack stellt diese Aktionen bereit: **Ankunft an einem Ort erfassen**, **Abfahrt von einem Ort erfassen**, **Timer starten** (optional mit Art und Ort) und **Timer stoppen**. Auch per Siri: „Ankunft in Büro erfassen mit Timetrack“.

iOS erlaubt Apps nicht, eine persönliche Automation selbst anzulegen. In der App hilft dir deshalb **Kurzbefehl erstellen** (je Ort und auf der Standortautomatik-Seite) mit drei Schritten und dem Ortsnamen zum Kopieren:

1. Kurzbefehle, Reiter **Automation**, **+**, **Ankunft** (oder **Verlassen**) und deinen Ort wählen.
2. Aktion **Timetrack, Ankunft an einem Ort erfassen** mit demselben Ort wählen.
3. **Sofort ausführen** wählen.

Wichtig: Wenn du beide Wege für denselben Ort einschaltest, erkennt Timetrack die doppelte Ankunft und bucht nur einmal. Du brauchst aber nur einen der beiden Wege. Kurzbefehle sind sinnvoll, wenn du keinen Standortzugriff „Immer“ geben möchtest.

Ohne Standortzugriff kann die App den Aufenthalt nach der Wartezeit nicht selbst prüfen: Dann gilt der Auslöser der Kurzbefehle als Beleg.

## Grenzen

- Bezeichnungen in der Kurzbefehle-App können je nach iOS-Version abweichen.
- Die Erkennung hängt von iOS ab: Sie kann sich um Minuten verzögern, und in Funklöchern oder bei sehr kleinen Orten kann ein Ereignis ausbleiben. Fehlende Abfahrten beendet die App nicht von selbst; es erscheint später ein Vorschlag für das Ende.
- Akkuverbrauch und Zuverlässigkeit im Alltag sind noch nicht gemessen.
