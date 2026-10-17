# timetrack-apple

Native Apps von **Timetrack**, einer selbst gehosteten Arbeitszeiterfassung (AGPL-3.0-only): SwiftUI-Apps für macOS, iOS/iPadOS und watchOS (mit Komplikation, Widgets, Live Activity und Steuerzentrale), Zielplattformen OS 27, Liquid Glass nach Apple HIG. Die Apps sprechen die REST-API des Timetrack-Backends.

> **Status: Alpha.** Alle Plattformen sind implementiert (Pakete A1–A8) und in Simulatoren geprüft, aber noch nicht auf Echtgeräten. TestFlight: Archiv und Export lokal bestätigt, Upload steht aus. Details und Lücken: [docs/STATUS.md](docs/STATUS.md).

## Aufbau

- `Packages/TimetrackCore`: Modelle, API-Client, Anmeldung, Stores, Sync (ohne UI)
- `Packages/TimetrackDesign`: Designsprache (Tokens, Komponenten, Darstellungsseite), siehe [docs/DESIGN-NATIVE.md](docs/DESIGN-NATIVE.md)
- `Sources/Mac`, `Sources/iOS`, `Sources/Watch`, `Sources/Widget*`: die Apps und Erweiterungen
- `project.yml`: XcodeGen-Definition; `Timetrack.xcodeproj` wird daraus erzeugt (und ist eingecheckt)
- App-Symbole: [docs/ICONS.md](docs/ICONS.md)

## Lokal starten

Voraussetzungen: Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen), ein erreichbares Timetrack-Backend (z. B. lokal aus dem Backend-Repo).

```sh
xcodegen generate
open Timetrack.xcodeproj
# Paket-Tests
(cd Packages/TimetrackCore && swift test --build-system native)
(cd Packages/TimetrackDesign && swift test --build-system native)
```

Für Signierung ist ein Apple-Developer-Team nötig; Team und Kennungen stehen in `project.yml` und sind für eigene Builds anzupassen. Die Passkey-Anmeldung setzt voraus, dass das Backend `APPLE_APP_IDS` gesetzt hat und die Datei `apple-app-site-association` unter der Serverdomain ausliefert (siehe Backend `docs/DEPLOYMENT.md`).

## Repositories

| Repository | Rolle |
| --- | --- |
| [timetrack-backend](https://github.com/MagicalWig34653/timetrack-backend) | Hauptrepo: Backend, API-Vertrag, Konzept, ADRs (ADR-0015 für native Clients), Arbeitsplan |
| [timetrack-pwa](https://github.com/MagicalWig34653/timetrack-pwa) | Weboberfläche |
| timetrack-apple (dieses) | Apple-Apps |

## Mitarbeit, Sicherheit, Lizenz

Bitte vor größeren Änderungen ein Issue anlegen (nur synthetische Daten). Sicherheitslücken nicht öffentlich melden, sondern über die private Meldung von GitHub (siehe `.github/SECURITY.md`). Lizenz: [GNU AGPL-3.0-only](LICENSE). Das Repository enthält keine externen Swift-Abhängigkeiten.
