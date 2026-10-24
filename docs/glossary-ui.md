# Glossar der Oberflächenwörter (UX3, 20.10.2026)

Festgelegt vom Entwickler (Nutzerentscheidung: Wortwahl liegt beim Entwickler, einheitlich und dokumentiert). Gilt für iOS, iPadOS, macOS, watchOS, Widgets und Live Activity. Backend-Wörter (Segment, Zeitabschnitt, evaluated) erscheinen nie in der Oberfläche.

| Begriff | Bedeutung | Nicht verwenden |
| --- | --- | --- |
| **Eintrag** | Ein Zeitraum mit Art, Beginn und Ende (Backend: Segment). Mehrzahl „Einträge“. Der laufende Eintrag heißt „Timer“. | Zeitabschnitt, Abschnitt, Segment |
| **Timer** | Der gerade laufende Eintrag („Kein Timer läuft“, „Timer starten“). | Stoppuhr, „Zeitabschnitt läuft“ |
| **Fortführen** | Den letzten beendeten Eintrag von heute wieder öffnen, sodass die Zeit ohne Lücke weiterläuft („Fortführen: Arbeit, zuletzt bis 12:03“). Gleich auf allen Plattformen: Heute (iPhone, iPad, Mac), Jetzt-Sheet und Leiste (iPhone), Mac-Menü „Zeit“ (⌥⌘C), Symbolleiste und Menüleisten-Fenster, Apple Watch, Kurzbefehle/Siri „Letzten Timer fortführen“, Widget und Steuerzentrale. Kann der Server das nicht, beginnt ein neuer Eintrag ab jetzt und die Lücke bleibt eine Pause; die App sagt, was passiert ist. Unterschied zu „Weiter“ (Toast nach Stopp, Pause beenden): „Weiter“ legt immer einen neuen Eintrag an. | wiederaufnehmen, fortsetzen, Rückgängig (für Stopp) |
| **Aktivitätserfassung** | Lokale, freiwillige Aufzeichnung (nur Mac), welche App im Vordergrund war, solange ein Timer läuft. Ansicht „Aktivität“. Verlässt den Mac nie; wirkt nur über **Vorschläge**, die du prüfst und bestätigst. | Tracking, Überwachung, Spionage |
| **Regel (Aktivität)** | „Wenn diese App läuft, gehört die Zeit wahrscheinlich zu Art / Projekt / Lernfeld.“ Erzeugt nur Vorschläge. | Automatik, Zuordnung (ohne Vorschlag) |
| **Nur Menüleiste** | Mac-Modus ohne Dock-Symbol; das Menüleisten-Symbol öffnet das Fenster bei Bedarf. | Hintergrundmodus, Agent |
| **Art** | Arbeit, Fahrt, Schule. | Typ, Kategorie |
| **Abwesenheit** | Urlaub, Krank, Freigestellt, Sonstiges. „Eintrag“ meint nie eine Abwesenheit. | Eintrag (für Abwesenheit) |
| **Gearbeitet** | Arbeitszeit des Tages nach Pausen und Rundung, inklusive Schulgutschrift (Backend: evaluated + credit). Format immer h:mm. | Erfasst, bewertet (nur in Erklärungen) |
| **Soll** | Geplante Arbeitszeit des Tages laut Arbeitsmodell. | Ziel, Pensum |
| **noch X bis Soll / X darüber** | Wie weit der Tag vom Soll entfernt ist (ersetzt „Differenz“ auf Heute). Vor dem ersten Eintrag steht nur „Soll X“. | Differenz, Defizit, Minus (auf Heute) |
| **Zeitkonto** | Mehr- und Minderzeit insgesamt; plus heißt Guthaben. | Saldo, Überstundenkonto |
| **vorläufig** | Der Tag ist nicht abgeschlossen; Pausen und Rundung können sich noch ändern. Per Tipp erklärt. | unvollständig, ungültig |
| **Feierabend** | Geplantes Ende des Arbeitstags (Live Activity). | Planende |
| **Mehr** | Sammelbereich (Berichtsheft unter „Ausbildung“, Auswertung und Export, Freigaben, Erinnerungen, Automatik, Einstellungen). | Einstellungen (als Tabname) |
| **Berichtsheft** | Wochenbericht der Ausbildung (BH1): pro Woche Einträge mit Lernfeld, Zeit und Notizen; Status der Woche „Entwurf“/„Erledigt“ (nur Markierung). „Berichtszeit“ ist die Summe der Einträge und nicht „Gearbeitet“. Aktion „Für IHK-Portal kopieren“. | Bericht (allein), Tätigkeitsnachweis |
| **Lernfeld** | Eigene Liste des Kontos (Nummer optional, Name); Einträge behalten den Namen als Momentaufnahme. | Fach, Kategorie |
| **Quellen** | Notizen und Dateien einer Berichtswoche als Material; nie geteilt. | Anhänge (die gehören zu Abwesenheiten) |
| **Arbeitsmodell-Version** | Ein Gültigkeitszeitraum des Arbeitsmodells (Soll, Rundung, Schule, feste Pausen). „Neue Version anlegen“ gilt ab einem Tag, die laufende Version endet am Vortag; „Beenden“ setzt nur den letzten Gültigkeitstag (z. B. Ausbildungsende); „Korrigieren“ überschreibt eine Version (mit Vorschau). Die Historie bleibt immer erhalten. | Modell (allein), Segment-Version |
| **Korrektur (Zeitkonto)** | Datierte Gutschrift oder Abzug auf dem Zeitkonto mit Begründung; kann nicht gelöscht, nur mit einer Gegenbuchung ausgeglichen werden. **Anfangsstand**: Stand, ab dem das Zeitkonto zählt (nur einer). | Saldo, Buchung rückgängig |
| **Statistik** | Diagramme unter Mehr: Zeitkonto-Verlauf, „Soll und Gearbeitet“, „Mehr- und Minderzeit“, „Verteilung nach Art“, Abwesenheiten, Pausen. „Mit Rundung“/„Ohne Rundung“ wählt, ob Rundung von erstem Beginn und letztem Ende mitzählt. | Auswertung (für die Statistik; „Auswertung und Export“ bleibt der Web-Bereich) |
| **Im Web** | Bereich, den es nur in der Web-App gibt; Zeile öffnet sie im Browser. | – |

Farben der Abwesenheiten (UX3): Urlaub smaragdgrün, Krank rose, Freigestellt teal, Sonstiges schiefergrau, Feiertag amber; Arten: Arbeit sky, Fahrt amber, Schule violett. Farbe ist nie die einzige Information (Symbol und Name stehen daneben).

## Noch nicht vereinheitlicht (liegt in Zeit-Tab/Kalender, Folgepaket nach Z2)

| Stelle | Heute | Soll |
| --- | --- | --- |
| `plan.action.segment`, `plan.sheet.segment`, `plan.short.segment` (Kalender) | Zeitabschnitt (hinzufügen) | Eintrag |
| `calendar.evaluation_text` | „Soll X, bewertet Y“ | „Soll X · gearbeitet Y“ |
| `wk.day.future`, `wk.day.no_work`, `wk.week.empty_text` (Woche) | „erfasst“ | „gearbeitet“ bzw. „eingetragen“ |
| Mac-Inspector `inspector.*`, `void.many` (AD1.xcstrings) | Abschnitte/Zeitabschnitte | Einträge |
| `today.delta` („Differenz“), Wochen-/Tageszeilen im Zeit-Tab | Differenz | „noch X offen“ (neutral) oder „X fehlen“ (nur vergangene Tage) |
| Kalender-Aktion „Termin als Zeitabschnitt vorschlagen“ (E1) | Zeitabschnitt | Eintrag |
