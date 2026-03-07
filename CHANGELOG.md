# Changelog

## 0.3.0

### Added
- Dedicated `TOMLConfigDocument` for canonical flat dotted config parsing and serialization
- Bundle ID migration plan in `docs/plans/bundle-id-migration.md`

### Changed
- Bundle identifier moved from `com.trnscrb.app` to `com.janwillemaltink.trnscrb`
- Primary keychain service moved to `com.janwillemaltink.trnscrb.credentials.v3`
- Existing saved secrets are intentionally not migrated; they must be re-entered once
- OSLog subsystem aligned with the new app identity
- Release packaging now signs the DMG before notarization when using a Developer ID
- Settings/config persistence aligned with the flat schema work in PR #5

## 0.2.0

**Breaking:** Minimum deployment target raised from macOS 14 (Sonoma) to macOS 26 (Tahoe).

### Added
- Custom menu bar panel replacing NSPopover for better positioning and dismissal behavior
- Full keyboard navigation: arrow keys to browse jobs, Delete/Backspace to remove, Cmd+V to paste files, Cmd+W/Escape to close
- Unified file import system supporting drag-and-drop, paste from Finder, and file picker with promise-file materialization
- Output file name formatter for consistent naming
- Dedicated settings window (separated from the menu panel)
- Notarization status checker script
- New tests for panel layout, file import, file picker presentation, output naming, and delivery

### Changed
- AppDelegate refactored: lazy dependency composition, clearer lifecycle
- Settings UI redesigned with grouped form sections
- Transcription routing updated for local provider selection
- Settings normalization gains additional validation rules

### Removed
- SettingsSectionCard (replaced by grouped form sections)
- NSPopover-based panel architecture
