# Checkliste: Live Activity im Smart Stack der Apple Watch (Siri-Stapel)

Die Watch zeigt die Live Activity des iPhones automatisch (watchOS 11+ mit iOS 18+); eine App kann das Spiegeln nicht erzwingen und nicht abschalten (Apple Developer Forums, Thread 765634). Die Anzeige hängt daher an Einstellungen auf beiden Geräten. Der Reihe nach prüfen, nach jedem Punkt einen Timer (Arbeit) starten:

1. **Voraussetzungen:** iPhone und Watch gekoppelt und verbunden (Watch zeigt kein rotes Telefon-Symbol), iOS und watchOS gleiche Hauptversion (27), Timer läuft, auf dem iPhone ist die Live Activity sichtbar (Sperrbildschirm/Dynamic Island).
2. **iPhone > Einstellungen > Timetrack > Live Activities** an (und „Häufige Aktualisierungen“ ist nicht nötig). Einstellungen > Mitteilungen > Timetrack: Mitteilungen erlaubt.
3. **iPhone > Watch-App > Mein Watch > Siri-Stapel (Smart Stack) > Live Activities:** Schalter an; in der Liste darunter Timetrack an. (Bezeichnung je nach Version „Live Activities“ oder „Live-Aktivitäten“.)
4. **Watch > Einstellungen > Siri-Stapel > Live Activities** an; Timetrack in der App-Liste an. Auf der Watch auch **Einstellungen > Mitteilungen > Timetrack** prüfen (Mitteilungen spiegeln: „Spiegeln von iPhone“ bzw. eigene Einstellungen).
5. **Bildschirm der Watch:** Die Karte erscheint im Siri-Stapel (Digital Crown nach oben drehen oder vom Zifferblatt nach oben wischen), nicht als Komplikation. Bei gesenktem Handgelenk/Always-On bleibt sie sichtbar, wird aber abgedunkelt; „Aktivität bei gesenktem Handgelenk“ (Einstellungen > Display & Helligkeit > Always-On) an.
6. **Fokus/Kinomodus/Flugmodus:** Ein Fokus kann Spiegeln unterdrücken; zum Test ausschalten. Die Watch muss das iPhone erreichen (Bluetooth/WLAN), sonst kommt keine Aktualisierung.
7. **Neu laden:** Timer beenden, Live Activity im Smart Stack wegwischen, Timer neu starten. Hilft das nicht: Watch neu starten, danach iPhone neu starten (der Spiegelkanal wird bei der Kopplung neu aufgebaut).
8. **Watch-App:** Timetrack auf der Watch installiert und aktuell (Watch-App im selben Build wie die iPhone-App). Antippen der Karte öffnet derzeit die iPhone-App (kein `WKSupportsLiveActivityLaunchAttributeTypes` gesetzt).

Ergebnis melden: Welcher Punkt hat es (nicht) geändert? Sieht man auf der Watch eine abgekürzte Karte (Symbol und Uhr links/rechts, wie die kompakte Dynamic Island) oder gar keine? Eine abgekürzte Karte hieße: die Spiegelung funktioniert, nur das `.small`-Layout wird nicht verwendet; keine Karte hieße: Spiegelung selbst blockiert (Einstellung/Kopplung/System).
