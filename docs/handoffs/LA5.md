# Handoff LA5: Live Activity fehlt im Smart Stack der Watch

Branch `la5-watch-smartstack` (von `main`, Build 35), 23.10.2026. Nicht gemergt, nicht gepusht, keine Build-Erhöhung, kein Upload.

## Befund (belegt)
- **Keine Konfigurationsänderung seit der Version, die funktionierte.** Die Smart-Stack-Konfiguration (`ActivityConfiguration` mit `.supplementalActivityFamilies([.small])`, `@Environment(\.activityFamily)`, `NSSupportsLiveActivities` in App und Erweiterung, `Activity.request(... pushType: nil)`, Standard-Stil, `staleDate: nil`) ist seit Build 9 (LA1) unverändert. Diff Build 14 (LA3) bis Build 35: in den Widget-Dateien nur LA4 (`LiveKindIcon`, Standard Aus: gleiches SF Symbol wie zuvor), Fonts in `UIAppFonts`, ein zusätzliches Control (H5) und `OverworkScheduler.sync` (OT1). `project.yml`: Watch ist eingebettet, `WKCompanionAppBundleIdentifier` stimmt, Deployment 27.0 durchgehend.
- Das ausgelieferte Archiv von Build 35 (`~/.cache/timetrack-testflight`) enthält Watch-App und beide Erweiterungen; `NSSupportsLiveActivities` ist in der iOS-Erweiterung gesetzt.
- Der Nutzerbericht zu LA2/LA3 belegt, dass der Smart Stack in Build 12/13 die Karte zeigte (LA3: "Nutzerfeedback Build 13"). Der Bruch liegt also nach Build 13/14.
- Nach Apple (Dokumentation `ActivityFamily`, Forum 765634): Spiegeln auf die Watch ist automatisch, nicht abschaltbar durch die App, Schalter liegen beim Träger.

## Nicht belegt (Hypothesen)
Eine Code-Ursache im Repo wurde **nicht gefunden**. Wahrscheinlichste Gründe, nach Gewicht:
1. Einstellung/Kopplung/OS: Smart-Stack-Schalter (Watch-App und Watch), Mitteilungen, Fokus, OS-Update (iOS/watchOS 27.x) oder neu gekoppelte Watch. Vom Repo aus nicht prüfbar; siehe `docs/guides/watch-smart-stack.md`.
2. Die `.small`-Ansicht kann auf der Watch nicht gerendert werden (LA3-Layout mit `ViewThatFits`, festen Uhrgrößen, Intent-Knöpfen). Dann zeigt watchOS zwar etwas, aber nicht die Karte; unbestätigt, da nur Näherung in der Galerie.
3. Apple-Beispiel deklariert `[.small, .medium]`; wir hatten nur `[.small]`. Ob das ein Unterschied macht, ist unbekannt.

## Nachtrag nach Nutzerprüfung
Der Nutzer bestätigt: Smart-Stack-Schalter und App-Erlaubnis sind an, trotzdem keine Karte. Damit rückt der Code in den Vordergrund. Wichtig: Das letzte **auf der Uhr bestätigte** Layout ist LA2 (Build 13). Das LA3-Layout (Build 14, `ViewThatFits` über `ForEach`, `fixedSize`, `dynamicTypeSize`-Begrenzung, eigene Kreis-Knöpfe mit `.plain`) wurde nie auf einer Uhr gesehen und ist der einzige größere Unterschied der `.small`-Ansicht; sonst hat sich an Konfiguration, Plists, Targets und `Activity.request` nichts geändert. Daher: `.small` auf LA2-Bausteine zurückgeführt (Titel-Schrift mit `minimumScaleFactor`, kein `ViewThatFits`/`fixedSize`/Dynamic-Type-Begrenzung), drei kompakte Zeilen und runde Knöpfe bleiben. **Hypothese, nicht bewiesen**; ohne Gerät nicht prüfbar. Falls die Karte weiterhin fehlt, ist der nächste Schritt, `.small` testweise auf ein reines `Text`-Layout zu reduzieren (bisektiert Layout gegen System) und die Geräte-Konsole (`chronod`) zu lesen.

## Geändert (Absicherung, Wirkung am Gerät unbestätigt)
- `.supplementalActivityFamilies([.small, .medium])` wie in Apples Beispiel; Familienwahl mit ausdrücklichem `.small`, `.medium` und `@unknown default` (statt `default`), ohne Jokerzweig (Apple-Forum 776101).
- DEBUG-Hook `TT_DEV_LA_FORCE=1` (startet eine Beispiel-Activity ohne Sitzung).
- Neu: `LiveActivityWatchConfigTests` (Plist-Schlüssel, Watch-Begleiter und Einbettung, Familienbehandlung, kein `.transient`).
- Neu: `docs/guides/watch-smart-stack.md` (Checkliste für das Gerät).

## Reproduktion
Gekoppelte Simulatoren (iPhone 18 Pro + Watch Series 12) gebaut, installiert, Activity per Hook gestartet. **Nicht aussagekräftig**: headless Screenshots zeigen weder Activity noch Smart Stack (wie schon LA4), es gibt keine Eingabe, um den Siri-Stapel zu öffnen. Reproduktion nicht möglich.

## Prüfung
Siehe STATUS-Zeile; Kerntests, iOS-/macOS-/watchOS-Builds unsigniert.

## Nächster Schritt am Gerät
Checkliste abarbeiten. Falls die Watch eine abgekürzte (Inselartige) Karte statt des `.small`-Layouts zeigt, ist Hypothese 2/3 relevant; zeigt sie gar nichts, ist es Hypothese 1. Dann gezielt: Geräte-Konsole (Xcode > Window > Devices and Simulators > Open Console, Filter `chronod`, `ActivityKit`) beim Start eines Timers.
