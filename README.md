# trnscrb

A macOS menu bar app that converts audio recordings, PDFs, and images (including handwritten notes) into clean, well-formatted markdown — with a single drag-and-drop gesture.

## How It Works

Drop a file onto the menu bar icon (or into the menu panel drop zone), and trnscrb handles the rest:

1. **Resolves** provider mode for that media type: **Cloud** (Mistral) or **Local** (Apple on-device, macOS 26+)
2. **Cloud mode:** sends the file to Mistral for transcription or OCR
3. **Local mode (macOS 26+):** processes on-device
4. If “Mirror originals to S3” is enabled in Advanced Pipeline, the original file is copied to your S3-compatible bucket after processing (best-effort; failures surface as warnings)
5. **Delivers** markdown to your configured outputs: it always saves a `.md` file and can also copy to the clipboard
6. **Cleans up** S3 objects automatically after 24 hours when mirroring was used

## Supported File Types

| Category   | Formats                             | Provider options                                               |
| ---------- | ----------------------------------- | -------------------------------------------------------------- |
| **Audio**  | mp3, wav, m4a, ogg, flac, webm, mp4 | Mistral Voxtral Mini (Cloud), or Local Apple (macOS 26+) |
| **PDF**    | pdf (scanned & digital)             | Mistral OCR 3 (Cloud), or Local Apple OCR (macOS 26+)      |
| **Images** | png, jpg, jpeg, heic, tiff, webp    | Mistral OCR 3 (Cloud), or Local Apple OCR (macOS 26+)      |

## Key Design Principles

- **Per-media provider selection** — audio, PDF, and image each have independent mode selection (Local vs Cloud); modeled as extensible options (not a hardcoded toggle).
- **BYOK (Bring Your Own Key)** — no subscription; Cloud mode uses your Mistral API key; S3 is used only when “Mirror originals to S3” is enabled.
- **Parallel batch processing** — drop multiple files at once; they all process concurrently with per-file progress tracking.
- **Privacy-first** — API keys stored in macOS Keychain, config lives in Application Support with one-time legacy XDG migration, no telemetry, no analytics.

## Tech Stack

- **Swift 6** with **SwiftUI**, targeting **macOS 26+**
- Clean Architecture: domain layer with use cases and gateway protocols, infrastructure layer with concrete implementations (`S3Client`, `MistralAudioProvider`, `MistralOCRProvider`, `AppleSpeechAnalyzerProvider`, `AppleDocumentOCRProvider`, `KeychainStore`, etc.)
- Native `URLSession` for networking, Swift Concurrency (`async/await`, `TaskGroup`) for parallelism

## Install

```bash
brew tap jwa91/tap
brew install --cask trnscrb
```

Requires macOS 26 or later.
