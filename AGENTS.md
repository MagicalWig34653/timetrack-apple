# Timetrack – Client-Repository

Das Backend ist Hauptrepo und kanonisches Projektgedächtnis: `<workspace>/timetrack-backend (Pfad in der eigenen Umgebung)`.
Vor Aufgaben dort AGENTS.md, docs/STATUS.md, docs/ARBEITSPLAN.md,
docs/ENTWICKLUNGSABLAUF.md und relevante Konzepte/ADRs lesen; zusätzlich hier docs/STATUS.md.
Falls das Hauptrepo fehlt, zunächst dessen Checkout bereitstellen; nicht aus Chat-Memory weiterarbeiten.
API-Verträge liegen im Backend unter contracts/. Keine unabhängigen globalen Konzeptkopien.
Claude koordiniert; Ziel war etwa 50 % Umsetzung durch Codex (tatsächlicher Anteil ca. 19,5 %, Details im Backend `docs/ARBEITSPLAN.md`; Codex schreibt nicht in diesem Repo).
Dateibesitz pro Agent klar trennen. Fragen ausschließlich im normalen Chat.
Ergebnisse/Prüfungen lokal und globale Auswirkungen im Backend dokumentieren.
Keine Secrets oder persönlichen Daten committen. Sessions müssen wegwerfbar bleiben.
Das Repo ist öffentlich: Commit-Autor ist die Pseudonym-Identität des Projekts (Git-Konfiguration nicht ändern); keine privaten E-Mail-Adressen, Pfade, Hostnamen oder IP-Adressen. Bundle-ID, Team-ID und Domain in `project.yml` sind funktional nötig und bleiben (im Gegensatz zum Backend-Repo, das Platzhalter nutzt). Name: Projekt Timetrack; „Chronolog“ nur App-Store-Eintrag.
Stand der Apps, Befehle, Signierung, TestFlight: `docs/STATUS.md`; Designsprache: `docs/DESIGN-NATIVE.md`; Übergaben: `docs/handoffs/`.

Code, Kommentare, Tests und technische Bezeichner auf Englisch; nutzerseitige Texte auf Deutsch.
Verbindliche Details stehen im Backend unter docs/ENTWICKLUNGSABLAUF.md,
Abschnitt „Sprache von Code und Oberfläche“. An alle beauftragten Agents weitergeben.
