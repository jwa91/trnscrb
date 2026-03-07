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
   VERSION="0.3.1"
   printf '%s\n' "$VERSION" > VERSION
   ```

2. Commit and tag:

   ```bash
   VERSION="0.3.1"
   git add -A && git commit -m "Bump version to $VERSION"
   git tag "v$VERSION"
   git push origin main "v$VERSION"
   ```

3. Build the DMG (signed with Developer ID):

   ```bash
   make clean && make dmg IDENTITY="Developer ID Application: Jan Willem Altink (U3ST8HC98U)"
   ```

   Verify the app bundle identifier before notarizing:

   ```bash
   /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/trnscrb.app/Contents/Info.plist
   # expected: com.janwillemaltink.trnscrb
   ```

   The `dmg` target now signs the disk image as well when `IDENTITY` is a real Developer ID.

4. Notarize and staple:

   ```bash
   VERSION="0.3.1"
   xcrun notarytool submit "build/trnscrb-$VERSION.dmg" \
     --keychain-profile "notarytool" --wait
   xcrun stapler staple "build/trnscrb-$VERSION.dmg"
   ```

   > **Note:** Notarization is handled by Apple's servers and can take minutes to hours.
   > First-time submissions with a new Developer ID may take significantly longer.
   > Once Apple has processed an initial submission, subsequent ones are typically fast.

   If Apple is backlogged and `--wait` is impractical, submit without `--wait`,
   publish the signed DMG temporarily, and keep the Homebrew quarantine-removal
   workaround in place. Then use the read-only checker:

   ```bash
   VERSION="0.3.1"
   scripts/notarization-status.sh --version "$VERSION"
   ```

   Example cron entry to check every 30 minutes:

   ```cron
   */30 * * * * cd /Users/jw/developer/trnscrb && scripts/notarization-status.sh --version 0.3.1 >> /tmp/trnscrb-notarization.log 2>&1
   ```

   If you created the GitHub release before notarization completed, replace the release asset after Apple reports `Accepted`:

   ```bash
   VERSION="0.3.1"
   xcrun stapler staple "build/trnscrb-$VERSION.dmg"
   gh release upload "v$VERSION" "build/trnscrb-$VERSION.dmg" --clobber
   SHA=$(shasum -a 256 "build/trnscrb-$VERSION.dmg" | awk '{print $1}')
   ```

   Then update `Casks/trnscrb.rb` in `homebrew-tap`:
   - replace `sha256`
   - remove the temporary `postflight` quarantine workaround block

5. Create a GitHub Release:

   ```bash
   VERSION="0.3.1"
   gh release create "v$VERSION" "build/trnscrb-$VERSION.dmg" --title "v$VERSION"
   ```

   If you had to publish before notarization completed, rerun `gh release upload "v$VERSION" "build/trnscrb-$VERSION.dmg" --clobber` after stapling the accepted DMG.

6. Update the Homebrew tap:

   ```bash
   VERSION="0.3.1"
   SHA=$(shasum -a 256 "build/trnscrb-$VERSION.dmg" | awk '{print $1}')
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
make IDENTITY="Developer ID Application: Jan Willem Altink (U3ST8HC98U)"
```

Store notarytool credentials once (avoids passing Apple ID/password each time):

```bash
xcrun notarytool store-credentials "notarytool" \
  --apple-id "janwillemaltink@gmail.com" \
  --team-id "U3ST8HC98U"
```
