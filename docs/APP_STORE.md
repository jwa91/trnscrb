# Mac App Store Release

This flow is separate from the Developer ID DMG/Homebrew release in [RELEASING.md](RELEASING.md). Use the `trnscrb-AppStore` Xcode target for TestFlight and Mac App Store uploads.

## Prerequisites

- Apple Developer team `U3ST8HC98U` configured in Xcode.
- App Store Connect app record for bundle ID `com.janwillemaltink.trnscrb`, category Productivity, SKU `trnscrb-macos`.
- Privacy policy URL: `https://janwillemaltink.com/trnscrb/privacy`.
- App Store signing assets available through Xcode automatic signing.

## Validate

Run the package suite directly:

```bash
swift test
```

Run the Xcode compatibility scheme. This builds a small Xcode test bundle and runs the SwiftPM suite from a build phase, so the command stays compatible with the existing release check:

```bash
xcodebuild test \
  -scheme trnscrb \
  -destination 'platform=macOS,arch=arm64' \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 30
```

Check the App Store target without requiring signing:

```bash
xcodebuild build \
  -project trnscrb.xcodeproj \
  -scheme trnscrb-AppStore \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

## Archive And Upload

Create a signed archive for App Store Connect:

```bash
rm -rf build/trnscrb-AppStore.xcarchive build/AppStore
xcodebuild archive \
  -project trnscrb.xcodeproj \
  -scheme trnscrb-AppStore \
  -destination 'generic/platform=macOS' \
  -archivePath build/trnscrb-AppStore.xcarchive
```

Verify the archive contains an app bundle, not a command-line product:

```bash
test -d build/trnscrb-AppStore.xcarchive/Products/Applications/trnscrb.app
```

Upload through Xcode Organizer or export/upload with:

```bash
xcodebuild -exportArchive \
  -archivePath build/trnscrb-AppStore.xcarchive \
  -exportPath build/AppStore \
  -exportOptionsPlist Support/AppStoreExportOptions.plist
```

For a local unsigned archive shape check only:

```bash
rm -rf /tmp/trnscrb-appstore-check.xcarchive
xcodebuild archive \
  -project trnscrb.xcodeproj \
  -scheme trnscrb-AppStore \
  -destination 'generic/platform=macOS' \
  -archivePath /tmp/trnscrb-appstore-check.xcarchive \
  CODE_SIGNING_ALLOWED=NO
find /tmp/trnscrb-appstore-check.xcarchive/Products -maxdepth 4 -print | sort
```

## App Store Connect Metadata

Screenshots must use a Mac 16:10 size, preferably `2880x1800`. Capture:

- Menu bar icon and drop panel.
- Settings with Local/Cloud provider choices.
- A completed markdown output result.

Privacy answers:

- No tracking.
- No sale of data.
- User-selected files are sent to Mistral only when Cloud mode is enabled.
- Original-file uploads to S3-compatible storage happen only when the user enables mirroring and configures their own S3 endpoint/bucket.
- Mistral and S3 credentials are stored locally in Keychain.

Review notes:

> trnscrb is a menu bar app with no Dock window. Launch it, click the menu bar icon, open Settings, leave all file types set to Local, then use Add Files or drag a sample PDF/image/audio file onto the panel. Cloud mode requires a user-provided Mistral key; S3 mirroring is optional and can remain off.

## Manual Sandbox QA

- Fresh install with no config.
- One-time migration from legacy `~/.config/trnscrb/config.toml`.
- Choose a Documents output folder, restart, then write again to verify the security-scoped bookmark.
- Local audio, PDF, and image processing.
- Cloud Mistral processing with a user-provided test key.
- Optional S3 mirroring with a user-configured S3-compatible endpoint.
- Notifications, reveal/open saved file, and menu bar review path.
