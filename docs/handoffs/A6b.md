# Handoff A6b: app icon

Branch `a6b-icon`. Added: `Icons/` (source SVGs, 5 `.icon` bundles), `scripts/icons/build_icons.py`, `Sources/iOS/AppIconSettingsSection.swift`, `docs/ICONS.md`, additive `project.yml` edits (marked `# A6b`).

## Integration for the lead (after A6 is merged)
1. project.yml merge: keep A6's targets; re-apply the `# A6b` lines: per target `sources` entries `Icons/Timetrack*.icon` with `buildPhase: resources` (iOS all five, Mac and Watch Primary only), and `ASSETCATALOG_COMPILER_APPICON_NAME: TimetrackPrimary` (all three) plus `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (iOS).
2. A6's `AppIcon` asset set is replaced by the primary `.icon`: remove its `.xcassets` AppIcon entry or at least ensure no `AppIcon` name remains in `ASSETCATALOG_COMPILER_APPICON_NAME`.
3. In `Sources/iOS/SettingsView.swift` add `AppIconPickerSection()` as a child of the `Form`/`List` (e.g. before the account/logout section). It has no dependency on the design package; restyle if wanted.
4. `xcodegen generate`, build the three schemes.
