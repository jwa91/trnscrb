# trnscrb Website Brief

## Goal

Create a small public website at `https://trnscrb.janwillemaltink.com` that supports the Mac App Store submission and gives users a clear place to learn what trnscrb does, get help, read the privacy policy, and find non-App-Store installation options.

The site should be simple, fast, and static. It does not need accounts, analytics, tracking pixels, forms, or cookies.

## Required Pages

### Home / Support

URL: `https://trnscrb.janwillemaltink.com`

Purpose:

- App Store Support URL.
- Product landing page.
- Quick start guide.
- Links to GitHub and Homebrew install instructions.
- Clear note that Cloud mode requires a user-provided Mistral API key.

Recommended sections:

1. Hero
   - Short title: `Transcribe PDFs, images, and audio from your Mac menu bar.`
   - Short subtitle: `trnscrb turns selected files into clean Markdown using local Apple frameworks where available, or Mistral when you choose Cloud mode.`
   - Primary link: `Download on the Mac App Store` once live.
   - Secondary link: `View on GitHub`.

2. What It Does
   - Converts PDFs, images, and audio files to Markdown.
   - Runs from the macOS menu bar.
   - Saves output to a folder you choose.
   - Supports local processing where available.
   - Supports Cloud mode with a user-provided Mistral API key.
   - Optionally mirrors original files to user-configured S3-compatible storage.

3. Install
   - Mac App Store install link once available.
   - GitHub release link for direct download if still supported.
   - Homebrew command if still supported:

   ```bash
   brew tap janwillemaltink/trnscrb
   brew install --cask trnscrb
   ```

   Confirm the exact tap/cask command before publishing.

4. Cloud Mode / Mistral API Key
   - Explain that Cloud mode is optional.
   - Explain that users need their own Mistral API key.
   - Suggested steps:
     - Create or sign in to a Mistral account.
     - Open the Mistral API keys page.
     - Create an API key.
     - Paste it into trnscrb Settings.
     - Keep the key private and rotate it if it is exposed.
   - Link to Mistral’s official console/docs.

5. Support
   - Basic troubleshooting:
     - If the menu bar icon is not visible, launch trnscrb from Applications and check the menu bar.
     - If saving fails after changing folders, choose the output folder again in Settings.
     - If Cloud mode fails, verify the Mistral key and network connection.
     - If S3 mirroring fails, verify endpoint, bucket, access key, and secret key.
   - Contact:
     - Use a real email address or GitHub Issues link.
   - Link:
     - `GitHub Issues` for bug reports.

6. Privacy Link
   - Prominent footer link to `https://trnscrb.janwillemaltink.com/privacy`.

7. Project / Author Links
   - Add a footer link to the author homepage:
     - Label: `Made by Jan Willem Altink`
     - URL: `https://janwillemaltink.com`
   - Optionally add a donation/support link:
     - Label: `Support development`
     - URL: the real Buy Me a Coffee page, if published and intended for this project.
   - Keep the donation link clearly optional. Do not frame it as payment for app functionality, support priority, subscriptions, unlocks, or access to features.

### Privacy Policy

URL: `https://trnscrb.janwillemaltink.com/privacy`

Purpose:

- App Store Privacy Policy URL.
- Clear user-facing disclosure of local processing, Cloud mode, Mistral uploads, optional S3 mirroring, and Keychain credential storage.

This page must be publicly accessible and should not require JavaScript, login, a cookie banner, or app installation.

Recommended content:

1. Summary
   - trnscrb does not track users.
   - trnscrb does not sell personal data.
   - trnscrb does not include advertising.
   - Local mode processes selected files on the user’s Mac.
   - Cloud mode sends selected files or extracted content to Mistral for transcription/OCR.
   - S3 mirroring, if enabled, uploads original files to storage configured by the user.

2. Data The App Handles
   - User-selected PDFs, images, and audio files.
   - Generated Markdown output.
   - Local app settings.
   - Mistral API key, stored locally in Keychain.
   - Optional S3 endpoint, bucket, access key, and secret key, with secrets stored locally in Keychain.

3. Local Processing
   - When Local mode is selected and available, files are processed on device using Apple frameworks.
   - Output is saved to the user-selected folder.
   - Settings are stored locally in Application Support.

4. Cloud Processing With Mistral
   - When Cloud mode is selected, the app sends selected files or content to Mistral to perform transcription/OCR.
   - The user provides their own Mistral API key.
   - Users should review Mistral’s privacy/data handling terms.
   - Link to Mistral’s privacy policy and terms.

5. Optional S3 Mirroring
   - If enabled, original files are uploaded to a user-configured S3-compatible endpoint and bucket.
   - trnscrb does not provide the S3 storage account.
   - Users control the endpoint, bucket, and credentials.

6. Credentials
   - API keys and secret keys are stored locally in macOS Keychain.
   - The app does not intentionally transmit credentials except as needed to authenticate with the configured service.

7. Retention
   - Generated output remains where the user saves it.
   - Local settings remain on the Mac until the user removes them.
   - Data sent to Mistral or S3-compatible storage is subject to those providers’ retention policies and the user’s account configuration.

8. Contact
   - Provide a real contact email or GitHub Issues link.

9. Effective Date
   - Include a date and update it when privacy practices change.

## Footer

Use the same footer on both pages:

- `Privacy Policy`
- `GitHub`
- `Support`
- `Made by Jan Willem Altink`
- Optional: `Support development`
- Optional: `Mac App Store` once live

## App Store Connect Values

Use these once the pages are live:

- Support URL: `https://trnscrb.janwillemaltink.com`
- Marketing URL: `https://trnscrb.janwillemaltink.com` or leave blank
- Privacy Policy URL: `https://trnscrb.janwillemaltink.com/privacy`

## Copy Constraints

- Do not claim that no files ever leave the device. Cloud mode and optional S3 mirroring can upload user-selected files.
- Do not imply that Mistral or S3 are operated by trnscrb.
- Do not say the app is App Store approved until it is approved.
- Do not publish Homebrew commands until the exact tap/cask command has been verified.
- Do not use the Buy Me a Coffee page as the App Store Support URL, Marketing URL, or Privacy Policy URL.
- Keep any donation link on the website optional and separate from app functionality.
- Keep “Local mode” and “Cloud mode” language consistent with the app UI.
