## Was ändert dieser Pull Request?

<!-- Kurz, auf Deutsch. Verweis auf Issue, ADR oder Arbeitspaket. -->

## Prüfung

- [ ] `xcodegen generate` ohne Diff; `swift test` der Pakete; Builds der geänderten Schemes (CODE_SIGNING_ALLOWED=NO)
- [ ] Bei API-Nutzung: Abgleich mit `contracts/openapi.yaml` im Backend-Repository
- [ ] Dokumentation mitgepflegt (`docs/STATUS.md`, betroffene Fachdokumente, ggf. ADR)

## Projektregeln

- [ ] Code, Kommentare, Tests und Bezeichner auf Englisch; Oberfläche und nutzerseitige Texte auf Deutsch
- [ ] Keine echten personenbezogenen Daten, keine Geheimnisse; Testdaten sind synthetisch
- [ ] Kontentrennung gilt auch für MCP, Exporte, Anhänge, Jobs, Suche und Push
- [ ] Vorschläge sind nicht als Nutzerentscheidungen dargestellt; offene Details sind kenntlich
