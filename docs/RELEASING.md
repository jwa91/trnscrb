# Releasing

## Prerequisites

- [Homebrew](https://brew.sh) installed
- `gh` CLI authenticated (`gh auth login`)

## Build

```bash
make          # build + assemble .app + codesign
make dmg      # create distributable DMG
```

The version is read from the `VERSION` file at the project root. The build number is derived automatically from the git commit count.

## Release a new version

1. Update the version:

   ```bash
   echo "0.2.0" > VERSION
   ```

2. Commit and tag:

   ```bash
   git add -A && git commit -m "Bump version to 0.2.0"
   git tag v0.2.0
   git push origin main v0.2.0
   ```

3. Build the DMG (signed with Developer ID):

   ```bash
   make clean && make dmg IDENTITY="Developer ID Application: REDACTED_DEVELOPER_IDENTITY"
   ```

   Verify the app bundle identifier before notarizing:

   ```bash
   /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/trnscrb.app/Contents/Info.plist
   # expected: com.janwillemaltink.trnscrb
   ```

   The `dmg` target now signs the disk image as well when `IDENTITY` is a real Developer ID.

4. Notarize and staple:

   ```bash
   xcrun notarytool submit build/trnscrb-0.2.0.dmg \
     --keychain-profile "notarytool" --wait
   xcrun stapler staple build/trnscrb-0.2.0.dmg
   ```

   > **Note:** Notarization is handled by Apple's servers and can take minutes to hours.
   > First-time submissions with a new Developer ID may take significantly longer.
   > Once Apple has processed an initial submission, subsequent ones are typically fast.

   If Apple is backlogged and `--wait` is impractical, submit without `--wait`,
   publish the signed DMG temporarily, and keep the Homebrew quarantine-removal
   workaround in place. Then use the read-only checker:

   ```bash
   scripts/notarization-status.sh --version 0.2.0
   ```

   Example cron entry to check every 30 minutes:

   ```cron
   */30 * * * * cd /Users/jw/developer/trnscrb && scripts/notarization-status.sh --version 0.2.0 >> /tmp/trnscrb-notarization.log 2>&1
   ```

   Once Apple reports `Accepted`, finish the release manually:

   ```bash
   xcrun stapler staple build/trnscrb-0.2.0.dmg
   gh release upload v0.2.0 build/trnscrb-0.2.0.dmg --clobber
   SHA=$(shasum -a 256 build/trnscrb-0.2.0.dmg | awk '{print $1}')
   ```

   Then update `Casks/trnscrb.rb` in `homebrew-tap`:
   - replace `sha256`
   - remove the temporary `postflight` quarantine workaround block

5. Create a GitHub Release:

   ```bash
   gh release create v0.2.0 build/trnscrb-0.2.0.dmg --title "v0.2.0"
   ```

6. Update the Homebrew tap:

   ```bash
   SHA=$(shasum -a 256 build/trnscrb-0.2.0.dmg | awk '{print $1}')
   ```

   Edit `Casks/trnscrb.rb` in the [homebrew-tap](https://github.com/jwa91/homebrew-tap) repo — update `version` and `sha256`.
   If notarization is still pending, keep the temporary `postflight` block.
   After notarization is accepted, remove it manually.

## Install via Homebrew

```bash
brew tap jwa91/tap
brew install --cask trnscrb
```

## Makefile targets

| Target         | Description                          |
| -------------- | ------------------------------------ |
| `make`         | Build, assemble `.app`, and codesign |
| `make build`   | Compile release binary               |
| `make app`     | Assemble `.app` bundle               |
| `make sign`    | Codesign the `.app`                  |
| `make dmg`     | Create and sign `.dmg` for distribution |
| `make install` | Copy `.app` to `/Applications`       |
| `make verify`  | Verify codesign integrity            |
| `make clean`   | Remove build artifacts               |

## Signing

By default the app is signed ad-hoc (local use). For distribution, sign with the Developer ID:

```bash
make IDENTITY="Developer ID Application: REDACTED_DEVELOPER_IDENTITY"
```

Store notarytool credentials once (avoids passing Apple ID/password each time):

```bash
xcrun notarytool store-credentials "notarytool" \
  --apple-id "REDACTED_EMAIL" \
  --team-id "REDACTED_TEAM_ID"
```
