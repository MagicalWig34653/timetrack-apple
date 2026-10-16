# Handoff A6c: icon redesign and accents

Branch `a6c-icon-accents`. Replaces A6b's arc/hand icons with the navy/closed-blue-ring/white-L design in 6 accents plus a light-surface option. Touched: `Icons/` (new bundles, source, preview-variants.png), `scripts/icons/build_icons.py`, `Sources/iOS/AppIconSettingsSection.swift`, new `Sources/iOS/IconPreviews.xcassets`, `project.yml` (`# A6c`), docs.

## Integration for the lead (after A6 is merged)
1. Merge project.yml: keep A6's targets, re-apply the `# A6b`/`# A6c` lines (iOS: 7 icon bundles as resources + `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`; Mac/Watch: Primary only + `ASSETCATALOG_COMPILER_APPICON_NAME: TimetrackPrimary`). `xcodegen generate` afterwards (the committed pbxproj is regenerated).
2. Remove A6's own `AppIcon` asset set if still present.
3. Add `AppIconPickerSection()` to `Sources/iOS/SettingsView.swift` (still not wired).
4. `IconAccent.accents` (hex strong/light) can drive the in-app accent colour later.
5. Open question: the "Hell" variant relies on dark hands; without working dark specializations they are barely visible in the system Dark/Tinted appearances. Consider dropping it.
