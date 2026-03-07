# Bundle ID Migration Plan

## Goal

Rename the app bundle identifier from `com.trnscrb.app` to a long-term stable identifier before wider distribution, without disrupting the current direct distribution, signing, notarization, Homebrew install flow, or local configuration.

## Migration Policy

This project is currently treated as pre-release and effectively single-user.

Decision:
- Prefer clean breaks over backward-compatibility layers during migration work.
- If an old local config or secret store conflicts with the new implementation, reset the local data instead of adding compatibility code.

## Recommended Target

Use `com.janwillemaltink.trnscrb`.

Reasoning:
- It follows Apple reverse-DNS convention.
- It is backed by a domain you control: `janwillemaltink.com`.
- It does not require creating a live DNS record or subdomain.
- It is clearer and more durable than `com.trnscrb.app`.

Note on subdomains:
- If you think of the app as `trnscrb.janwillemaltink.com`, the reversed bundle ID is still `com.janwillemaltink.trnscrb`.
- Bundle identifiers are naming conventions, not URLs.

## Current State

- Bundle ID is set in `Support/Info.plist`.
- The app bundle is assembled manually via `Makefile`, not by an Xcode project.
- Distribution signing uses `Developer ID Application: Jan Willem Altink (U3ST8HC98U)`.
- Notarization uses `notarytool` with team `U3ST8HC98U`.
- Entitlements file is currently empty.
- Config is stored in `~/.config/trnscrb/config.toml`, not in a bundle-ID-derived location.
- Keychain secrets use a new service name with no backward-compatibility path.
- Homebrew cask installs `trnscrb.app` and does not reference the bundle ID.

## Verification Checklist

- `build/trnscrb.app/Contents/Info.plist` reports `com.janwillemaltink.trnscrb`
- About screen shows the new bundle ID
- `codesign -dvvv build/trnscrb.app` reports the new identifier
- `spctl -a -vv build/trnscrb.app` accepts the app
- Existing config still loads from `~/.config/trnscrb/config.toml`
- New secrets are stored under the new keychain service name
- Launch at Login can be toggled successfully
- Local notifications still work
- The DMG is code-signed before notarization
