# Stand der Apple-Apps – 17.10.2026

Projektstatus: **Alpha**. Das Repository ist seit 17.10.2026 öffentlich (AGPL-3.0-only). Kanonisches Projektgedächtnis (Konzept, ADRs, Arbeitsplan, API-Verträge) liegt im Backend-Repo (`<workspace>/timetrack-backend`, `docs/STATUS.md`, `docs/ARBEITSPLAN.md`, ADR-0015 für die nativen Clients). Dieses Dokument beschreibt den tatsächlichen Stand der Apps; Details je Paket in `docs/handoffs/`.

## Pakete und Stand (alle integriert in `main`)

| Paket | Inhalt | Zahlen/Belege laut Handoff |
| --- | --- | --- |
| A1 | Swift-Paket `TimetrackCore` (Modelle, API-Client, Auth, Stores) und macOS-App (Heute, Zeit, Einstellungen, Menüleiste) | 43 Tests inkl. Integrationstest gegen Wegwerf-Backend |
| A3 | iOS/iPadOS-App (Heute, Zeit, Urlaub lesend, Einstellungen, Quick Actions, App Intents) | 50 Tests; UI-Smoke auf iPhone- und iPad-Simulator |
| A4 | watchOS-App (direkt zum Server, Sitzung per WatchConnectivity vom iPhone) | 59 Tests; Simulator-Lauf; WatchConnectivity nur gegen Mock |
| A5 | Watch: Art-Auswahl, Komplikation (WidgetKit, App Group, nicht geheimer Snapshot), iPhone-Knopf „Sitzung an Uhr senden“ | 69 Tests; Komplikation nur in der Galerie |
| A6 | Designschicht `TimetrackDesign` und neu gestaltete Oberflächen, App-Symbol | 69 + 3 Tests |
| A6b/A6c | Symbol im Icon-Composer-Format, Akzent-Varianten, Auswahlansicht (`docs/ICONS.md`) | Primärvorschau gesichtet, Dark/Tinted-Spezialisierungen von den Werkzeugen ignoriert |
| A6d | Darstellungsseite: App-Akzent und App-Symbol getrennt wählbar, Erscheinungsbild System/Hell/Dunkel | 69 + 11 Tests (Kontrast ≥ 4,5:1) |
| A7 | Widgets (Home-/Sperrbildschirm, interaktiv), Live Activity, Steuerzentrale, macOS-Widgets | 72 + 11 Tests; **nur kompiliert**, nur Debug-Galerie gesichtet |
| A8 | Akzent und Erscheinungsbild aus dem Konto (`GET/PATCH /me/preferences`, Vertrag v0.14.0, ADR-0020) mit lokalem Cache, Akzent im Widget-Snapshot | 93 Kerntests + 14 Design-Tests; „Heute“ nach Neuinstallation mit Konto-Akzent gesichtet |
| A10 | Planung nativ: Kalender-Tab, Abwesenheiten anlegen/bearbeiten/stornieren (Urlaub, Krank mit Krankschein-Stand, Freigestellt, Sonstiges), Urlaubseinstellungen, Schnellaktionen auf Heute (`docs/handoffs/A10.md`) | 112 Kerntests + 14 Design-Tests; iOS-UI-Durchlauf auf iPhone (hell/dunkel) und iPad; macOS nur gebaut |
| A9 | Absturz beim Stornieren in „Zeit“ (TestFlight 0.0.1 (1)) behoben: `swipeActions` mit `role: .destructive` + später geänderte Daten verletzten die UICollectionView-Stapelaktualisierung; zudem eine Zeilenliste je Tag mit stabilen IDs, Storno entfernt lokal in einem Schritt; Build 0.0.1 (2) | Reproduziert und behoben im Simulator (iPhone, iPad), Regressionstest `VoidSegmentTests`; Gerät nicht erneut geprüft, siehe `docs/handoffs/A9.md` |
| H1 | Haptisches Feedback: zentrale Schicht in `TimetrackDesign`, Ergebnis-Meldungen der Stores, Einstellung Aus/Dezent/Normal (`docs/handoffs/H1.md`) | 120 Kern- + 22 Design-Tests; Smoke/Void-UI-Tests grün; **Gefühl auf Gerät/Uhr nicht geprüft** |
| F2 | Fokus-Filter (iOS): `SetFocusFilterIntent` mit Modus Nachfragen/Automatisch/Nichts tun, Art, Ort; Rückfragen als Mitteilung mit Aktionen; Erklärseite, Protokoll, Testknöpfe; Anleitung `docs/guides/fokus-filter.md` (`docs/handoffs/F2.md`) | 137 Kerntests (Wahrheitstabelle); UI-Test im Simulator; **echter Fokus, Mitteilungen im Fokus und Aktionsknöpfe nicht geprüft** |
| W1 | GitHub-Actions-Workflows, Vorlagen, TestFlight-Gerüst (`docs/handoffs/W1.md`) | actionlint; Workflows laufen auf GitHub |

Die Backend-Seite (A2: `/.well-known/apple-app-site-association`, WebAuthn-Origin für native Apps) ist im Backend-Repo integriert.
Ziele: macOS 27, iOS/iPadOS 27, watchOS 27 (Deployment Target 27.0). Targets: `TimetrackMac`, `TimetrackIOS`, `TimetrackWatch`, `TimetrackWidget`, `TimetrackWidgetIOS`, `TimetrackWidgetMac`, `TimetrackIOSUITests`.

## Befehle

```sh
xcodegen generate                              # Timetrack.xcodeproj aus project.yml (XcodeGen 2.46.0)
(cd Packages/TimetrackCore && swift test --build-system native)    # 120 Tests (1 Integrationstest nur mit TT_INTEGRATION_URL)
(cd Packages/TimetrackDesign && swift test --build-system native)  # 22 Tests
xcodebuild -project Timetrack.xcodeproj -scheme TimetrackMac -configuration Debug CODE_SIGNING_ALLOWED=NO build   # analog TimetrackIOS (-destination 'generic/platform=iOS Simulator') und TimetrackWatch
```

Zuletzt vom Lead gemessen (Paket A8): Tests und Builds für iOS, macOS und watchOS erfolgreich (unsigniert). Beim Dokumentationsabgleich (D3) wurden keine Tests oder Builds neu ausgeführt.
Wegwerf-Backend für lokale Läufe: `scripts/seed-throwaway.py` (synthetische Daten). Symbole: `scripts/make-app-icon.swift`, `scripts/icons/` (siehe `docs/ICONS.md`). Texte: `scripts/add-strings.py`.

## Signierung und Kennungen (funktional, bleiben unverändert)

- Bezahltes Apple Developer Program: Team-ID und Bundle-ID stehen in `project.yml` (Bundle-Präfix `de.linolaske`, App-Gruppe `group.de.linolaske.timetrack`). Mit dem bezahlten Team wurde bestätigt, dass **Associated Domains** funktionieren (mit dem früheren persönlichen Team nicht; Debug-Konfiguration ohne Associated Domains bleibt vorhanden) und dass signierte Builds mit App Group (und gemeinsamer Keychain-Gruppe auf iOS) möglich sind.
- Für die Passkey-Anmeldung braucht das Backend `APPLE_APP_IDS` und die AASA-Datei muss unter der Produktionsdomain unverändert ausgeliefert werden (Backend `docs/DEPLOYMENT.md`). Auf der privaten Live-Testinstanz ist die AASA aus.
- Namensentscheidung (17.10.2026): Projekt und Anzeigename bleiben Timetrack; **Chronolog** ist nur der Name des App-Store-Connect-Eintrags („Chronolog – Arbeitszeit“). Die Bundle-ID bleibt, weil sie nach dem Anlegen nicht mehr änderbar ist.
- Ausfuhr: `ITSAppUsesNonExemptEncryption` ist als ausgenommen deklariert (Commit „Declare exempt encryption for TestFlight“).

## TestFlight

`scripts/testflight.sh <ios|mac> <archive|export|upload>` (lokal, Apple-ID aus Xcode, Team über `APPLE_TEAM_ID` überschreibbar, Ausgabe unter `~/.cache/timetrack-testflight`). **Archiv und Export wurden lokal bestätigt; der Upload ist noch nicht ausgeführt** und wartet auf die erreichbare AASA der Produktionsdomain. Die Build-Nummer (`CURRENT_PROJECT_VERSION` in `project.yml`, derzeit 1) muss bei jedem Upload steigen. `.github/workflows/testflight.yml` ist ein ungetestetes Gerüst (Secrets nur als Namen dokumentiert, in `docs/handoffs/W1.md` und Backend `docs/CI.md`).

## CI auf GitHub

`ci.yml` (XcodeGen-Drift, Paket-Tests, unsignierte Builds). Stand 17.10. auf `main`: **rot** – der gehostete Runner hat Swift 6.3.3, die Pakete verlangen Swift Tools 6.4 (Xcode 27); nur die XcodeGen-Drift-Prüfung ist grün. Lösung: Runner mit Xcode 27 (z. B. selbst gehostet, Repository-Variable `APPLE_RUNNER`) oder CI vorerst nicht als Pflichtprüfung führen. Auch der Dependabot-Lauf für die Swift-Pakete schlug fehl (Ursache nicht untersucht). Ein Pull-Request ist offen.

## Nicht geprüft / bekannte Lücken

- **Haptik (H1)**: Simulator spielt keine Haptik; Stärke und Abstimmung auf iPhone, Uhr und Mac-Trackpad ungeprüft.
- **Echtgeräte**: Passkey-Anmeldung (braucht Produktions-AASA), WatchConnectivity auf gekoppeltem Gerätepaar, Komplikation auf dem Zifferblatt, Widgets, Live Activity/Dynamic Island, Control Center, App Intents/Kurzbefehle, Keychain-Lesen aus Erweiterungen, VoiceOver, Dynamic Type auf allen Bildschirmen.
- **macOS-Client**: nur gebaut und teilweise als Fensterabbild gesichtet; keine vollständige visuelle Prüfung der Mac-Oberfläche; macOS-Widgets ungesehen.
- **Konto-Akzent (A8)**: Offline-/Fehlerzustände der Statuszeile, „Eigene Farbe“ per UI, Zwei-Geräte-Konflikt, Wechsel zwischen Konten mit ungesendeter Änderung (nur eine Cache-Marke). Native Farbtöne weichen bei Türkis/Orange/Rosa von der PWA ab (`docs/DESIGN-NATIVE.md`); die Watch-App selbst nutzt Standardblau, nur die Komplikation folgt dem Akzent.
- **Funktional nicht begonnen**: Kalenderbrücke (EventKit), lokale KI/KI-Worker, Standortautomatik (Region Monitoring) auf iOS, Offline-Schreiben.
- **Nutzerseitig/organisatorisch**: TestFlight-Upload, Betatester, App-Store-Metadaten, Datenschutzangaben und Lizenzprüfung im App-Store-Kontext.

## Dokumente in diesem Repo

| Datei | Inhalt |
| --- | --- |
| `README.md` | Überblick, Befehle |
| `AGENTS.md`, `CLAUDE.md` | Einstieg für Coding-Agents |
| `docs/DESIGN-NATIVE.md` | Native Designsprache (Tokens, Komponenten, Akzent-System, Abweichungen von der PWA) |
| `docs/ICONS.md` | App-Symbole und Akzent-Varianten |
| `docs/handoffs/` | Übergaben A1, A3–A10 (A6b–A6d), H1, W1 (A2 und die Backend-Seite liegen im Backend-Repo); Commit-Hashes darin sind seit der Historienbereinigung ungültig |
| `docs/screenshots/` | Simulator-Aufnahmen der Sichtprüfungen (synthetische Daten) |
