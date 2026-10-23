# Handoff HG1: Runloop-Hang von Build 36 (iPhone, iOS 27.0.1)

Branch `hg1-hang-fix` (von `main`, Build 36), 23.10.2026. Nicht gemergt, nicht gepusht, keine Build-Erhöhung, kein Upload.

## Befund (belegt, aus Report und dSYM)
Bericht: `UIKit-runloop-Timetrack-2026-10-23-124355.ips` (bug_type 328, "Completed Runloop Hang", 0,56 s, 56 Samples à 10 ms, Gerät iPhone18,1). Symbolisiert mit der passenden dSYM aus dem Archiv von Build 36 (UUID `6C315205-…` stimmt, `atos -l 0x100d34000`).
- **Es hängt nur der Main-Thread, und er rechnet** (CPU 0,398 s von 0,556 s; höchstens 1 von 56 Samples wartet). Alle anderen Threads sind praktisch untätig. Keine Sperre, kein Semaphor, kein `Task.sleep`, kein Netzwerk-/Datei-Lesen der App im Weg.
- 47 von 56 Samples (470 ms) liegen in SwiftUI/UIKit: 35 in `CA::Transaction::commit` → `_UIHostingView.layoutSubviews` (View-Graph-Update, Display-List, Layout), 11 in `ViewGraphHostUpdate.dispatchImmediately` (Body-Auswertung). Dabei wird eine **Tab-Hierarchie neu aufgebaut/umgehängt**: `UIKitAdaptableTabView.setTabs`, `_UITabContainerView _createViewHierarchy`, `UIKitTabBarController.viewDidMove(to:)` → `updateTabBarLayout` → verschachteltes Layout des Bottom-Accessory (15 Samples), UINavigationController/`prepareNavigationBar` (9), Textmessung (7, u. a. kalter ICU-Break-Iterator/`CoreNLP`-Ressourcen, 22 I/Os, 524 KB), Swift-Metadaten per Mangled Name (4).
- Eigener Code in den Stacks (symbolisiert): `TodayContent.body` (`TodayView.swift:35/62`), `dateLine`, Typmetadaten `QuickAbsenceRow`/`LazyState<AbsenceRequest?>`, `NowBarContent.body` (`NowBar.swift:47`, `onGeometryChange`), `StopToast.body` (`NowBar.swift:179`), `AppearanceModifier.body` (`@AppStorage`-Lesen, `AppearancePreferences.swift:99`) und das Wurzel-`Group { _ConditionalContent<NavigationSplitView, TabView…> }`. Das ist normale View-Konstruktion, keine einzelne Funktion, die blockiert.
- **Der einzige synchrone Systemaufruf in App-Code:** `TimetrackIOSApp.swift:61` (`Task { await AutomationRuntime.shared.refreshPlaces(…) }` auf dem Main-Actor) → `AutomationRuntime.store(for:)` (`AutomationRuntime.swift:142`) → `KeychainSecretStore.read` (`SecretStore.swift:50`) → `SecItemCopyMatching` → synchrones XPC an `securityd` (`xpc_connection_send_message_with_reply_sync`). Im Report 1 Sample (≤ 10 ms), aber unbeschränkt, sobald `securityd` beschäftigt ist.
- Umgebung: `Lost Perf: SKINTEMP 100 %` (Gerät thermisch gedrosselt, 0,78 c/i), Footprint 13,3 → 26,2 MB, 65 Page-ins, Shared-Cache-Residenz 17 %, "Time Since Fork" 1354 s.

## Nicht belegt (Hypothesen)
1. Auslöser des Tab-Neuaufbaus. Stimmig zu allen Indizien (Footprint verdoppelt sich, "type metadata completion" für `QuickAbsenceRow` erstmals, kalte Systemcaches, Page-ins): der Prozess lief seit 22 Minuten, die **erste sichtbare Oberfläche** wurde aber erst jetzt aufgebaut (Start im Hintergrund durch Region-/Focus-Ereignis, danach Öffnen durch den Nutzer). Dann wäre es der einmalige Kaltaufbau von `MainView` unter Drosselung. Alternative: Die Wurzelansicht wurde neu erzeugt, ihr `.task { await model.restore() }` lief erneut, `restore()` setzte `phase = .restoring` und riss die komplette angemeldete Oberfläche (Tabs, alle Stores) ab, um sie neu zu bauen. Aus dem Report allein nicht zu entscheiden.
2. Der Anteil des Keychain-Zugriffs an anderen Hängern ist nicht gemessen.

## Geändert (Wirkung am Gerät unbestätigt)
- `CachedSecretStore` (neu, `SecretStore.swift`): beantwortet Lesezugriffe der nur von der App geschriebenen Automatik-Schlüssel (`AutomationSecretKey.all`) aus dem Speicher; `prefetch()` läuft in `AutomationRuntime.start()` auf einem Hintergrund-Task. `AutomationRuntime` nutzt ihn für `engine`, `AutomationStore.init` (`hasLocalToken`), `deviceId` und die Token-Lesezugriffe der Seite. Sitzungsschlüssel (Server, Cookie) laufen weiter direkt durch (Widget, Intents und Watch-Übergabe schreiben sie).
- `AppModel.restoreIfNeeded()` (neu): ersetzt in `TimetrackIOSApp`/`TimetrackMacApp` den direkten `restore()`-Aufruf der Wurzel-`.task`. Ein angemeldetes Modell bleibt unangetastet (kein Umweg über `.restoring`, kein Abriss der Tab-Hierarchie); abgemeldet/offline versucht es weiter, nie zwei Läufe gleichzeitig. Auf dem Mac verhindert es zusätzlich, dass ein zweites Fenster alle Fenster auf "Lädt" zurücksetzt.
- Tests: `HangRegressionTests` (7): Cache liest je Schlüssel einmal, Schreiben/Löschen halten Cache und Basis gleich, andere Schlüssel nie veraltet, Prefetch wärmt alle, `restoreIfNeeded` lässt angemeldetes Modell (gleiche Stores, keine Session-Anfrage) unberührt, stellt gespeicherte Anmeldung einmal her, versucht offline erneut.
- Nicht geändert (bewusst, nicht belegt): kein Umbau der Tab-/Accessory-Struktur und keine Vorab-Aufwärmung von Text-/ICU-Ressourcen.

## Prüfung
`swift test --build-system native` (TimetrackCore): 562 Tests grün. Debug-Builds unsigniert: TimetrackIOS (Simulator), TimetrackMac, TimetrackWatch (Simulator) grün. Nicht auf dem Gerät geprüft.

## Nächster Schritt
Bei erneutem Hang denselben Report holen und prüfen, ob `MainView` erneut aufgebaut wird (`UIKitAdaptableTabView.setTabs` in den Stacks). Falls ja, mit Instruments (SwiftUI/Time Profiler) auf dem Gerät nach einem Hintergrundstart die erste Oberfläche messen; mögliche Entlastung: Today-Inhalt zuerst schlank (Skeleton) und Rest nachgeladen.
