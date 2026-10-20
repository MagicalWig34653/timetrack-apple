# UX2: Neues UI-Konzept auf Funktionsbasis (Konzept, kein Umbau)

Stand 20.10.2026, Basis `main` Build 22. Es wurde kein App-Code geändert (Z2 und PL1 arbeiten parallel am Zeit-Tab, Kalender und der Planung). Wireframes: `variante-a-heute.html`, `variante-b-kalender.html`, `variante-c-feed.html`, Flows: `flows.html` (statisch, ohne Skripte, Hell/Dunkel/System per Knopf).

**Grenzen:** Tap-Zahlen und Aufwand sind Schätzungen aus Code und Handoffs, nicht gemessen und nicht mit Nutzern getestet. Ob die Jetzt-Leiste (Tab-Bar-Zubehör) auf den Zielgeräten mit OS 27 wie gewünscht arbeitet, ist ungeprüft.

## 1. Funktionsinventar (aus Vertrag, Konzept, Handoffs) und nativer Stand

| Bereich | Funktionen (Backend) | Heute nativ (iOS) |
| --- | --- | --- |
| Zeiterfassung | Timer start/stopp, Arten, Abschnitte, Pausen, Korrektur/Storno mit Grund, Rundung (Roh/Korrektur/Bewertung), Tagesbewertung | Ja (Heute, Zeit); Rundung nur Anzeige/Modellblatt |
| Vorschläge | Zeitvorschläge (annehmen/ablehnen) aus Automatik | Teilweise (Standort-Automatik), Vorschlagsliste ungeprüft |
| Planung | Plantage, Wochenplan, Planfreigaben (Shares, eingehend) | Wochenplanung ja; Freigaben kaum |
| Abwesenheit/Urlaub | Konto (Anspruch, Übertrag, Korrekturen, Stichtag), Einträge, Planer-Vorschläge, Antrag/PDF-Vorlage, Anhänge, Krankschein | Konto, Einträge, Vorschläge ja; Antrag/PDF und Anhänge fehlen |
| Berichtsheft | Lernfelder, Einträge, Wochentext, Quellen | Praktisch nein (PWA) |
| Automatik | Orte, Modus direkt/Vorschlag/aus, Standort, Kurzbefehle, Kalenderbrücke, Fokus | Ja (Einstellungen) |
| Auswertung | Zeitkonto, Korrekturen, Export, Import | Zeitkonto ja; Export/Import nein |
| Konto/Admin | Passkeys, Wiederherstellung, Sitzungen, Module, Darstellung, Tokens/MCP | Teilweise (Module, Darstellung) |
| Mitteilungen | Benachrichtigungen, Push, lokale Erinnerungen | Erinnerungen ja |
| Umgebung | Live Activity, Widgets, Control Center, Watch, Komplikation, Menüleiste (Mac) | Ja, Geräteprüfung offen |

Heutige iOS-Struktur: 5 Bereiche (Heute, Zeit, Kalender, Urlaub, Einstellungen); iPad/Mac Sidebar (AD1); Einstellungen als lange Liste. Überschneidungen: Kalender, Urlaub und Planen sind drei Eingänge zum selben Thema; Jetzt (Timer) gibt es nur auf Heute (Mac ab AD1 in der Werkzeugleiste).

## 2. Aufgaben und Häufigkeit (Annahme, mit dem Nutzer zu bestätigen)

| Aufgabe | Häufigkeit | Anforderung |
| --- | --- | --- |
| Stempeln (Start/Stopp/Art) | mehrmals täglich | 1 Tap, überall, auch ohne App (Widget, Watch, Live Activity) |
| Tag prüfen/korrigieren | täglich | Abschnitte sehen, direkt ändern, Roh/Bewertet verstehen |
| Zeitkonto/Wochenstand ansehen | täglich bis wöchentlich | ohne Tippen sichtbar |
| Woche planen | wöchentlich | Tage setzen, schneller Standard |
| Bericht schreiben | wöchentlich | Wochenkontext, kopierbar |
| Urlaub planen/beantragen | monatlich bis jährlich | Bereich wählen, Konto-Folgen sehen, Antrag |
| Einstellungen/Konto/Module | selten | nicht im Hauptpfad |

Folgerungen: (1) „Jetzt“ ist keine Seite, sondern eine Aktionsleiste, die auf jedem Bereich sichtbar ist. (2) Seltenes (Einstellungen, Freigaben, Export, Automatik) gehört in einen Bereich „Mehr“ statt in die Tab-Leiste. (3) Gleiche Information einmal (Z1-Prinzip), Drill-down statt zweiter Liste.

## 3. Varianten

**A: Heute-zentriert** (`variante-a-heute.html`). Vier Räume: Heute, Verlauf (Tag/Woche/Konto als Zoom), Planung (Monat/Woche/Urlaub), Mehr (Berichtsheft, Auswertung/Export, Freigaben, Automatik, Einstellungen). Jetzt-Leiste über der Tab-Leiste. iPad/Mac: Sidebar Erfassen/Planen/Mehr plus Inspector (heutiges AD1-Muster). Watch/Widgets: nur Jetzt und Tagesstand. Begründung: passt zur häufigsten Aufgabe (Stempeln und Prüfen), nutzt vorhandene Teile (Z1, AD1, N1a), ist eine Evolution.

**B: Kalender-zentriert** (`variante-b-kalender.html`). Drei Räume: Kalender (Tag/Woche/Monat; Ist, Plan, Abwesenheit, Bericht je Tag), Konto (Zeit und Urlaub), Mehr. Begründung: Planung und Rückblick teilen ein Datumsmodell. Schwäche: Stempeln und „was ist jetzt?“ liegen im Tag-Zoom, schnelle Korrektur wird zum Kalenderdetail; Konto-Salden sind ein eigener Tab, also zwei Wege zu denselben Tageswerten.

**C: Timeline/Feed** (`variante-c-feed.html`). Eine Achse von Vergangenheit bis Zukunft mit Filter-Chips, dazu Planung, Konto, Mehr. Begründung: ein Ort für alles Zeitliche, modern. Schwächen: mischt Objekttypen (Abschnitt, Plan, Urlaub, Bericht), lange Listen, Planen und Salden brauchen trotzdem eigene Räume, Mac-Fenstermodell (Inspector) passt weniger, Lernkurve höher.

## 4. Tap-Zählung Top-Aufgaben (Details `flows.html`)

| Aufgabe | Heute | Variante A | B | C |
| --- | --- | --- | --- | --- |
| Stempeln (von anderem Tab) | 2 | 1 | 2 (Tag-Zoom) | 1 |
| Tag korrigieren | 4 | 3 | 4 | 4 |
| Woche planen | 5 | 4 | 4 | 5 |
| Urlaub planen | 5 | 4 | 4 | 5 |
| Zeitkonto ansehen | 2 | 0 bis 1 | 1 | 1 |
| Bericht schreiben (nativ) | nicht möglich (PWA, ca. 5) | 4 | 3 | 4 |

Fazit der Zählung: Der klare Gewinn ist die Jetzt-Leiste (Stempeln von überall) und der Bericht (existiert heute nativ nicht). Alles andere spart nur etwa einen Tap; das heutige Z1/AD1/N1a-Ergebnis ist schon nahe am Optimum.

## 5. Vergleich Konzept (A) gegen heutige App

| Kriterium | Heute (Build 22) | Variante A |
| --- | --- | --- |
| Hauptbereiche iPhone | 5 (inkl. Einstellungen) | 4 |
| Screens (Hauptzustände) | ca. 10 (Heute, Zeit+Wochendetails, Kalender+Tag, Urlaub+Planer, Wochenplaner, Einstellungen mit Unterseiten) | ca. 8 (Planung vereint Kalender, Urlaub, Planer) |
| Redundanz | gering nach Z1; Kalender/Urlaub/Planen noch drei Eingänge | gering; ein Planungsraum |
| Lernkurve | niedrig (bekannte Tab-Muster) | niedrig; leichte Umlernung (Urlaub und Kalender zusammen) |
| Umsetzungsaufwand | 0 | mittel: Jetzt-Leiste klein; Planung zusammenführen mittel (Konflikt mit PL1); Berichtsheft nativ groß (eigenes Paket, unabhängig vom Konzept); Mac-Sidebar nur umbenennen |
| Risiken | Berichte/Antrag fehlen nativ | Konflikt mit laufenden Paketen Z2/PL1; Bottom-Accessory-Verhalten auf OS 27 ungeprüft; Mehr kann zur Schublade werden; Regressions- und UI-Test-Anpassungen |

Varianten B/C im Vergleich: B spart einen Tab, kostet aber Stempelweg und Tagesprüfung; C ist der höchste Umbau (neuer Listentyp, Pagination, Filter) bei unklarem Nutzen. Beide schneiden bei den Top-Aufgaben nicht besser ab als A.

## 6. Empfehlung: in Teilen übernehmen (Variante A, ohne Neubau)

Neues Konzept komplett übernehmen lohnt nicht: es ist nur beim Stempeln und beim nativen Bericht deutlich besser, sonst etwa gleichwertig. Übernehmen:

1. **Jetzt-Leiste auf jedem Tab** (iPhone Tab-Bar-Zubehör; iPad/Mac Werkzeugleiste ist schon da). Größter Gewinn, kleiner Aufwand.
2. **Planung als ein Raum** (Kalender + Urlaub + Wochenplan, Zoom Monat/Woche/Urlaub): Tab-Zahl 5 auf 4, wenn „Mehr“ Einstellungen aufnimmt.
3. **„Mehr“ statt „Einstellungen“** als Sammelraum für Berichtsheft, Auswertung/Export, Freigaben, Automatik und Einstellungen.
4. **Berichtsheft nativ** als eigenes Funktionspaket (Backend-Endpunkte vorhanden), unabhängig vom Konzept dringlich.
5. Verwerfen: Variante B (Stempelweg schlechter), Variante C (hoher Umbau, kein Vorteil bei den Top-Aufgaben).

## 7. Migrationsplan (Schritte, jeweils eigener Build)

1. Nach Abschluss von Z2 und PL1: Jetzt-Leiste (iPhone) mit Start/Stopp und Art, Tests und TestFlight.
2. Tab „Einstellungen“ zu „Mehr“ ausbauen (Liste: Einstellungen, Automatik, Freigaben, Erinnerungen); ohne Funktionsänderung.
3. Berichtsheft nativ (Lernfelder, Wochen-Eintrag, kopierbarer Text) unter „Mehr“.
4. Kalender und Urlaub zu „Planung“ mit Zoom-Umschalter zusammenlegen (iPad/Mac: Sidebar-Einträge Kalender/Urlaub bleiben als Zoom-Ziele erhalten).
5. Antrag/PDF und Anhänge im Urlaubsablauf (Backend B7/B6 vorhanden).
6. Messung: echte Tap- und Zeitmessung mit dem Nutzer vor/nach Schritt 1 und 4; bei Nicht-Verbesserung Schritt 4 zurücknehmen.

## 8. Offene Punkte

- Häufigkeiten der Aufgaben sind Annahmen. Bestätigung durch den Nutzer fehlt.
- Watch und Widgets bleiben unverändert (nur Jetzt und Tagesstand); Geräteprüfung offen.
- Bildschirmgrößen, Dynamic Type und VoiceOver in den Wireframes nicht geprüft.
