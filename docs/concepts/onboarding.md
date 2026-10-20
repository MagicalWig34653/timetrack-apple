# Konzept: Onboarding (nicht gebaut, UX3)

Stand 20.10.2026. Nutzerentscheidung: vorerst kein Onboarding, nur ein kurzes Konzept. Bezug: UX1 F34/F35.

## Ausgangslage
Nach der Anmeldung steht der Nutzer auf „Heute“ mit leerer Liste. Arbeitsmodell, Urlaubsanspruch, Mitteilungen, Standort und Kalender werden nur in den Einstellungen erklärt; die Automatik (Alleinstellungsmerkmal) ist für neue Nutzer unsichtbar. Der Server ist Teil der Anmeldung (richtig für Selbstbetreiber).

## Vorschlag: drei überspringbare Schritte nach der ersten Anmeldung
1. **Arbeitsmodell prüfen.** Zeigt das vom Server gelieferte Modell (Wochen-Soll, Pausen) mit „Passt“ oder „Ändern“ (öffnet den vorhandenen Editor). Ohne Urlaubsanspruch: Karte „Urlaubsanspruch festlegen“ statt stiller Standardwerte (F17).
2. **Erinnerungen und Automatik erklären.** Je eine Karte, jeweils mit „Später“: Mitteilungen (Überstunden-Hinweise, Urlaubserinnerungen), Standortautomatik („Beim Ankommen Timer starten“, Berechtigung „Immer“ erst nach Erklärung), Kalender lesen. Berechtigungen werden erst beim Tippen auf „Aktivieren“ angefragt, nie vorab.
3. **Ersten Timer starten.** Zeigt die Jetzt-Leiste und den Start-Knopf; danach endet das Onboarding.

## Regeln
- Einmalig pro Konto und Gerät (Merker lokal, kein Server-Feld nötig); in „Mehr“ jederzeit wiederholbar („Einführung“).
- Kein Zwang, jeder Schritt mit „Überspringen“; keine Daten werden ohne Bestätigung geschrieben.
- Standardserver vorbelegen und „Eigener Server“ als stille Textaktion (F35) nur, wenn ein gehostetes Angebot besteht; offen, weil es die Entscheidung Selbsthoster gegen Hosting berührt.
- Texte nach `docs/glossary-ui.md`; VoiceOver und Dynamic Type von Anfang an prüfen.

## Aufwand und Reihenfolge
Etwa 3 bis 4 Tage (Karten-Flow, Merker, UI-Test, Texte). Sinnvoll nach dem Zusammenlegen von „Planung“ (Schritt 4–5), damit die Karten keine umbenannten Ziele erklären.

## Offene Fragen
1. Gibt es ein gehostetes Angebot (Standardserver)?
2. Soll das Onboarding auch auf Mac/iPad erscheinen oder nur auf dem iPhone?
