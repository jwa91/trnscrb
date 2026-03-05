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

3. Build the DMG:

   ```bash
   make clean && make dmg
   ```

4. Create a GitHub Release:

   ```bash
   gh release create v0.2.0 build/trnscrb-0.2.0.dmg --title "v0.2.0"
   ```

5. Update the Homebrew tap:

   ```bash
   SHA=$(shasum -a 256 build/trnscrb-0.2.0.dmg | awk '{print $1}')
   ```

   Edit `Casks/trnscrb.rb` in the [homebrew-trnscrb](https://github.com/jwa91/homebrew-trnscrb) repo — update `version` and `sha256`.

## Install via Homebrew

```bash
brew tap jwa91/trnscrb
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

By default the app is signed ad-hoc (local use). For distribution with a Developer ID:

```bash
make IDENTITY="Developer ID Application: Your Name (TEAMID)"
```
