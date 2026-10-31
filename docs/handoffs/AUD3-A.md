# Handoff AUD3-A: Paritätsfunktionen der Einstellungen (iOS/iPadOS/macOS)

Branch `aud3-a` (Worktree `timetrack-apple-wt/aud3-a`), von `main` bei Build 58. Nicht gepusht, Build-Nummer unverändert, kein Upload. Commits: `git log --grep "AUD3-A"` (Teil 1 Auslöse-Links, Teil 3 Profil, Teil 2 Konto und Sicherheit).

## Gebaut

### 1. Auslöse-Links (Vertrag 0.26.0, ADR-0027)
- iOS: Einstellungen › Automatik und Kalender › „Auslöse-Links“ (`settings.triggerlinks`). Mac: eigener Tab „Auslöse-Links“ (zeigt bei ausgeschaltetem Modul Automatik einen Hinweis).
- Liste (Bezeichnung, Aktionen, Art, Ort oder „ohne Ortsbindung“, Erstellt/zuletzt benutzt/Ablauf), Neuer Link (Bezeichnung, Aktionen start/stop/toggle mit Erklärung, Ort, Art, Gültigkeit 1 bis 730 Tage), Adressen nur einmal nach dem Anlegen (Kopieren, Teilen, je Aktion eine Adresse; Blatt nicht wegwischbar), Widerrufen mit Bestätigung, Sicherheitshinweise und Limit 20 wie in der PWA. Texte aus `de-trigger.ts`.
- Kern: `Models/TriggerLinks.swift` (`TriggerLink`, `TriggerLinkInput`, `TriggerLinkAddresses`, `TriggerAction`), `APIClient` (list/create/revoke), `TriggerLinksStore`. Token und Adressen bleiben nur im Speicher.
- Nicht übernommen: der Hilfeblock „Aufruf und Antworten“ der PWA (nur Entwicklerhinweis).

### 3. Profil (Vertrag 0.13.0)
- Seite „Profil“ unter „Konto und Sicherheit“: Anzeigename ändern (1 bis 80), Kontoname nur lesend, E-Mail hinzufügen/ändern mit Bestätigungscode, Code bestätigen, Adresse entfernen (Bestätigung), Hinweis ohne Mailversand, Konto-Karte folgt dem neuen Namen (`AppModel.applyDisplayName`).
- Frische Sitzung (403 `reauth_required`): `FreshLoginNotice` bietet „Mit Passkey erneut anmelden“ (`AppModel.reauthenticate`, nutzt die vorhandene Passkey-Anmeldung, ersetzt die Sitzung ohne Abmelden). Gilt auch für Teil 2.
- Zeitzone und Sprache: **nicht umgesetzt, weil nicht Teil des Profils im Vertrag**. Die Zeitzone hängt am Arbeitsmodell (steht schon unter „Server und Module“), die Apps sind nur Deutsch. Die Einrichtungs-Karte der PWA (`/onboarding`) fehlt nativ, weil es keinen nativen Einrichtungsassistenten gibt.

### 2. Konto und Sicherheit
- iOS: Einstellungen oben „Konto und Sicherheit“ (Hub mit Profil, Passkeys, Wiederherstellung, Verknüpfte Anmeldungen, Sitzungen). Mac: Tab „Konto“ mit demselben Hub.
- Passkeys: auflisten (älteste zuerst, erstellt/zuletzt genutzt), hinzufügen (Gerätename vorbelegt, vorhandene `PlatformPasskeyAuthenticator`, ohne die Sitzung anzufassen: `AuthService.registerAdditionalPasskey`), umbenennen, widerrufen (Warnung beim letzten Passkey, Serverfehler `last_passkey` wird gezeigt).
- Wiederherstellung wie PWA mit Vertrag 0.36.0: Recovery-Codes (erzeugen, neu erzeugen mit Warnung, ausschalten, Codes nur einmal anzeigen mit Kopieren/Teilen und „gespeichert“-Bestätigung, nie gespeichert), Rückfallpasswort (mindestens 12 Zeichen, Wiederholung, entfernen), E-Mail-Code = Konto-E-Mail (kein Adressfeld; `PUT /me/recovery/email` ohne Body, 204 sofort aktiv, 202 Codeeingabe; Zustände: nicht verfügbar, keine Kontomail, unbestätigt, aktivierbar, aktiv; Link ins Profil).
- Verknüpfte Anmeldungen (OIDC): auflisten und trennen (Bestätigung, `last_login_method` und Frische-Anmeldung abgefangen, Server ohne OIDC zeigt leere Liste). **Neu verknüpfen geht nur in der Web-App** (Anmeldung beim Anbieter läuft im Browser mit Weiterleitung auf die PWA; ein nativer Rückweg ist im Vertrag nicht vorgesehen). Die Seite sagt das.
- Sitzungen: nur „Andere Sitzungen abmelden“ (der Vertrag kennt keine Sitzungsliste, wie die PWA).
- Kern: `Models/AccountSecurity.swift`, `Models/Profile.swift`, `APIClient` (Profil, Passkeys, Recovery, Identitäten, Sitzungen; neuer interner `performWithStatus` für 202/204), Stores `ProfileStore`, `PasskeysStore`, `RecoveryStore`, `IdentitiesStore`, `SessionsStore`, neue Fehlercodes `too_many_trigger_links`, `email_taken`, `account_email_missing`, `recovery_email_must_be_account_email`, `last_login_method` mit deutschem Text.
- Verschoben: `SettingsRows.swift` von `Sources/iOS` nach `Sources/Settings` (wird jetzt auch vom Mac-Target genutzt).

### watchOS
Weggelassen (kein Passkey auf watchOS, keine Einstellungen für diese Funktionen). Watch-Build bleibt grün.

## Prüfung
- Kerntests (`swift test` in `Packages/TimetrackCore`): **985 grün** (vorher 938; neu 47: `TriggerLinksTests` 14, `ProfileTests` 13, `AccountSecurityTests` 20).
- Builds ungesigniert: TimetrackIOS (iOS-Simulator), TimetrackMac und TimetrackWatch grün (jeweils nach Teil 1, 3 und 2; Watch am Ende).
- Keine UI-Tests geschrieben und keine Simulatorläufe, **keine Bilder**.

## Nicht geprüft
- Gerät, VoiceOver, Dynamic Type, Mac-Oberfläche optisch, iPad-Layout.
- Passkey-Hinzufügen und Neu-Anmeldung (`reauthenticate`) brauchen echte Associated Domains und Gerät (siehe STATUS „Echtgeräte“); nur die Logik darum ist getestet (Stores mit eingespeister Ceremony).
- Lauf gegen ein echtes Backend 0.39.0 (nur Mock-Transport-Tests nach Vertrag); insbesondere E-Mail-Versand für Profil-/Recovery-Codes.
- Alle neuen Texte sind deutsche Literale im Code (wie bei den Kalenderabos), nicht im String Catalog; nur die fünf Fehlertexte im Kern-Katalog.

## Offen / Entscheidungen
- Einstellungen auf dem iPhone bekommen oben eine neue Zeile „Konto und Sicherheit“; ok?
- Nativer Weg zum Verknüpfen einer Identität bräuchte `ASWebAuthenticationSession` und einen Rücksprung-Vertrag im Backend.
- Kein Build-Nummer-Anstieg, kein TestFlight (Vorgabe).
