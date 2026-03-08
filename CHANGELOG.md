# Changelog

## 0.4.0

### Added
- Bucket mirroring toggle — S3 mirroring is now independent of processing mode
- Direct file upload to Mistral (audio and OCR) when mirroring is off, removing the S3 staging requirement
- Explicit pipeline stages (processing, mirroring, delivery) replacing the upload-centric job model
- Non-fatal mirror warnings — jobs complete even when S3 mirroring is misconfigured or unavailable
- Product model documentation (`docs/PRODUCT_MODEL.md`)
- Model diversification plan (`docs/plans/model-diversification.md`)
- `FileBackedMultipartBody` for sandbox-safe streaming uploads
- Capability-based transcription input handling — providers declare supported source kinds
- Extensive new test coverage for pipeline, provider, and settings validation

### Changed
- S3 credentials are only required when bucket mirroring is enabled, not for cloud processing
- Settings tabs reordered: Processing is now the default; Storage renamed to Advanced Pipeline
- "Copy S3 URL" renamed to "Copy Source URL"; S3-specific wording removed from UI
- Job status model replaced with distinct pipeline stage tracking
- Architecture and README updated to reflect the decoupled processing model
- TOML config gains `pipeline.mirroring.enabled` key with backward-compatible default
- TOML string escaping fixed for embedded control characters
- Release packaging now gates on tests passing before building DMG
- Release docs use 1Password CLI (`op`) instead of hardcoded credentials

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
