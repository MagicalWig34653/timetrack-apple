# Handoff A6d: Darstellung (Akzentfarbe, Erscheinungsbild, App-Symbol getrennt)

Branch `a6d-appearance` (von main nach A6/A6c), 16.10.2026. Nicht gemergt.

## Umgesetzt
- `TimetrackDesign`: `AccentDerivation` (Kontrastmathe, Ableitung fill/onFill/ink je hell/dunkel), `AccentChoice`/`SchemeChoice`/`AppearanceKeys`, `.ttAppearance()`, `AppearanceSettingsPage` (Vorschaukarte, Palette, ColorPicker, System/Hell/Dunkel, Transparenzhinweis, Slot für den Symbolbereich; nicht auf watchOS). `TTTheme` liefert `accent`, `onAccent`, `ink`; Buttons, Chips, Kennzahlen, Leerzustand nutzen `ink`/`onAccent`. System-`tint` = `ink`.
- iOS: `Sources/iOS/AppearanceView.swift` (Seite + `AppIconPickerSection` im `FormSection`), Zeile "Darstellung" in `SettingsView`; `AppIconPickerSection` ist jetzt reiner Inhalt (kein `Section`). macOS: Einstellungsfenster mit Tabs Allgemein/Darstellung; Hinweis, dass das Dock-Symbol dem Standardsymbol folgt. Konto-Avatar folgt dem Akzent (iOS, macOS).
- Heute (iOS/iPad/macOS): ein "vorläufig"-Chip bei "Erfasst" (Tag oder Zeitkonto vorläufig) statt je Kachel. Zeit-Tab unverändert (Chip je Tag).
- Strings in den iOS- und Mac-Katalogen (`appearance.*`, `settings.appearance`, `settings.general`); Watch-Katalog und `Sources/Watch`, `Sources/Widget*` unberührt. `project.yml` nicht geändert (Quellen per Verzeichnis); `Timetrack.xcodeproj` neu generiert.
- Test-Helfer: `Tests/iOSUI/AppearanceShotTests.swift` (Env `TT_SHOT_ACCENT`, `TT_SHOT_SCHEME`; setzt `-appearance.accent`/`-appearance.scheme` als Launch-Argumente).

## Hinweise für A7 / Lead
- Widgets/Komplikation lesen den Akzent nicht (UserDefaults.standard der App, nicht App Group). Falls Widgets den Akzent folgen sollen: Schlüssel in die App Group spiegeln.
- Merge: bei project.yml-Konflikten A7-Stand nehmen, A6d braucht keine Zeile.
- Offen: Swipe-Aktion "Bearbeiten" in Zeit nutzt `.tint(.accentColor)` (weiße Schrift auf Akzent; bei Orange/Graphit-hell ggf. schwach), Akzent nicht ins Konto synchronisiert.

## Für die Backend-Doku (Lead)
- docs/DESIGN.md: Verweis auf Apple-`docs/DESIGN-NATIVE.md`, Abschnitt Akzent-System (Ableitung wie PWA `accent.ts`; native Wahl lokal je Gerät, Presets Blau/Türkis/Violett/Grün/Orange/Rosa/Graphit/Eigene).
- ARBEITSPLAN/STATUS: A6d fertig auf Branch `a6d-appearance`; offen: Konto-Sync des Akzents (PWA speichert ggf. anders), Widget-Akzent.
