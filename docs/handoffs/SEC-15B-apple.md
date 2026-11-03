# SEC-15B Apple – Sitzungs-Cookiename nach Server-Schema

Stand: 03.11.2026. Basis `506af01`, Branch `apple-cookie-name`, nicht gemergt oder gepusht.
Auftrag: Todolino `55378E11-DB0E-4639-9EB2-3B000ADE818B`; hier keine Todolino-Werkzeuge verfügbar.
Backend-Verhalten: Vertrag 0.43.0, Backend-Handoff `docs/handoffs/SEC-15B.md`, ADR-0003.

## Umsetzung

- `Transport.swift`: `sessionCookieName(for:)` wählt bei HTTPS `__Host-tt_session`, sonst `tt_session`. Lesen akzeptiert nur den passenden Namen; Wiederherstellen setzt diesen Namen mit `Path=/` und Secure bei HTTPS. Kein Domain-Attribut ergänzt.
- Aufräumen entfernt beide Namen für den Server, auch Secure-Cookies beim Aufräumen einer HTTP-URL. Andere Cookies bleiben erhalten. `AuthService.signOut`, `clearSession`, `discardSession` und abgewiesene Wiederherstellung nutzen diesen Weg.
- Watch (`WatchHandoff`, `LaunchTrace`, `TimetrackWatchApp`): übertragen/lagern nur URL und Wert und verwenden denselben Transport; keine Änderung am Übertragungsformat nötig. Schlüsselbund-Schlüssel `session-cookie` bleibt unverändert.
- Widgets, Live-Activity-/Control-Intents (`WidgetSession`) und App Intents stellen über `AuthService`/`URLSessionTransport` wieder her; Snapshots enthalten keine Sitzung.
- Entwicklungsanmeldung: Kommentare und deutsche `Localizable.xcstrings` für iOS/Mac angepasst. HTTP-Seeds, `IntegrationTests` und `TT_DEV_COOKIE`-Kommentare für HTTP-Wegwerfserver bleiben korrekt.
- Keine Migration. Alte Backend-Sitzungen bleiben serverseitig ungültig und führen zur üblichen Neuanmeldung; kein Übernahmepfad für alte Cookies.

## Arbeitsort und Prüfungen

Der ursprüngliche Checkout ist in dieser Sandbox nicht beschreibbar (Anlegen einer Branch-Referenz verweigert).
Deshalb lokale Bare-Kopie `/private/tmp/timetrack-apple-cookie.git` und neuer verknüpfter Worktree
`/private/tmp/timetrack-apple-wt-cookie`; dessen Branch existiert nur in dieser Kopie.
Der Hauptcheckout bleibt unberührt. Vor Integration Commit aus der lokalen Kopie übernehmen.
Git-Autorenidentität des ursprünglichen Repositories beibehalten; keine Git-Konfigurationsdatei geändert.

Build-/Testkopie per `rsync -a` nach `/private/tmp/timetrack-apple-cookie-build`, ohne `.git`, `.build` oder Umgebungsdateien.
Keine iCloud-Duplikate erzeugt.

- Vollständige Core-Suite aus der Kopie: `CLANG_MODULE_CACHE_PATH=/private/tmp/timetrack-cookie-clang-cache swift test --build-system native --disable-sandbox --cache-path /private/tmp/timetrack-cookie-swiftpm-cache`: **1035 Tests in 148 Suites erfolgreich**. Zwei optionale Integrationstests ohne `TT_INTEGRATION_URL` übersprungen. Bestehende Continuation-Diagnose im Focus-Testlauf, trotzdem Exit 0.
- `SessionCookieTests`: 9 neue Fälle für HTTP/HTTPS, Lesen und Wiederherstellen mit Attributen, Ablehnen des alten HTTPS-Namens, Entfernen beider Namen, Abmelden/lokales Sitzungsende inklusive Schlüsselbund und Watch-Import.
- `git diff --check`: erfolgreich; beide geänderten String-Kataloge als JSON geprüft.
- Unsignierter iOS-Build versucht: `xcodebuild -project Timetrack.xcodeproj -scheme TimetrackIOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/timetrack-cookie-derived CODE_SIGNING_ALLOWED=NO build`. Zunächst Cache-Schreibrechte gesperrt; nach Umleitung der SwiftPM-/Modul-Caches bleibt Paketauflösung durch `sandbox-exec: sandbox_apply: Operation not permitted` blockiert. CoreSimulator ebenfalls nicht erreichbar. **Kein erfolgreicher iOS-Build**.

## Übergabe / nächster Schritt

Diff prüfen und Commit aus der lokalen Bare-Kopie übernehmen; vor Integration unsignierten iOS-Build außerhalb der Sandbox ausführen. HTTPS-Anmeldung, Neustart, Watch-Übergabe und Abmeldung am Gerät prüfen. Mac-/Watch-Builds und echte Backend-Integration nicht ausgeführt. Keine laufenden Jobs; kein Merge, Push oder TestFlight-Upload.
