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
   make clean && make dmg IDENTITY="Developer ID Application: Jan Willem Altink (U3ST8HC98U)"
   ```

4. Notarize and staple:

   ```bash
   xcrun notarytool submit build/trnscrb-0.2.0.dmg \
     --keychain-profile "notarytool" --wait
   xcrun stapler staple build/trnscrb-0.2.0.dmg
   ```

   > **Note:** Notarization is handled by Apple's servers and can take minutes to hours.
   > First-time submissions with a new Developer ID may take significantly longer.
   > Once Apple has processed an initial submission, subsequent ones are typically fast.

5. Create a GitHub Release:

   ```bash
   gh release create v0.2.0 build/trnscrb-0.2.0.dmg --title "v0.2.0"
   ```

6. Update the Homebrew tap:

   ```bash
   SHA=$(shasum -a 256 build/trnscrb-0.2.0.dmg | awk '{print $1}')
   ```

   Edit `Casks/trnscrb.rb` in the [homebrew-tap](https://github.com/jwa91/homebrew-tap) repo — update `version` and `sha256`.

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
| `make dmg`     | Create `.dmg` for distribution       |
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
