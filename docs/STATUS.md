# Lokaler Stand – 13.10.2026

Auf main: project.yml und generiertes Timetrack.xcodeproj; SwiftUI-Grundansicht.
macOS 27 und iOS/iPadOS 27 als Targets. Noch keine App-Fachfunktionen oder API-Anbindung.
xcodegen generate sowie xcodebuild -project Timetrack.xcodeproj -scheme TimetrackMac
-configuration Debug -derivedDataPath /tmp/timetrack-derived-data CODE_SIGNING_ALLOWED=NO build erfolgreich.
Kein iOS-Build, Geräte-/Signing-Test oder watchOS-Target. Keine laufenden Jobs.
Priorität bleibt PWA; native Funktionalität später zuerst macOS. Globaler Einstieg: ../AGENTS.md.
