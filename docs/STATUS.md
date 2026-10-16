# Lokaler Stand – 13.10.2026

Auf main: project.yml und generiertes Timetrack.xcodeproj; SwiftUI-Grundansicht.
macOS 27 und iOS/iPadOS 27 als Targets. Noch keine App-Fachfunktionen oder API-Anbindung.
xcodegen generate sowie xcodebuild -project Timetrack.xcodeproj -scheme TimetrackMac
-configuration Debug -derivedDataPath /tmp/timetrack-derived-data CODE_SIGNING_ALLOWED=NO build erfolgreich.
Kein iOS-Build, Geräte-/Signing-Test oder watchOS-Target. Keine laufenden Jobs.
Priorität bleibt PWA; native Funktionalität später zuerst macOS. Globaler Einstieg: ../AGENTS.md.

Nachtrag 14.10.2026: Sprachregel in AGENTS.md verbindlich ergänzt (Details im Backend).
Nur Dokumentation geändert; Diff geprüft, keine Builds erneut ausgeführt.
Lokalisierungsressourcen für die bisherigen direkt eingebetteten deutschen UI-Texte noch offen.

Nachtrag 16.10.2026 (Paket A1, Branch a1-core-mac, nicht gemergt): Swift-Paket Packages/TimetrackCore (Modelle, APIClient, AuthService, Stores),
macOS-App mit Heute, Zeit, Einstellungen und Menüleiste; Team J2DU2P47XW, Bundle-ID de.linolaske.timetrack. Tests: 42 Unit-Tests plus 1 Integrationstest
gegen einen Wegwerf-Backend (Port 18091) bestanden; macOS- und iOS-Simulator-Build erfolgreich (CODE_SIGNING_ALLOWED=NO), watchOS-Simulator-Build des Kerns erfolgreich.
Passkey-Anmeldung noch nicht testbar (Domain, Associated Domains, AASA im Backend fehlen). Oberfläche nicht visuell geprüft. Details: docs/handoffs/A1.md.
