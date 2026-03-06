# trnscrb

A macOS menu bar app that converts audio recordings, PDFs, and images (including handwritten notes) into clean, well-formatted markdown — with a single drag-and-drop gesture.

## How It Works

Drop a file onto the menu bar icon (or into the popover drop zone), and trnscrb handles the rest:

1. **Resolves** provider mode for that media type (`Mistral` or `Local Apple`)
2. **Mistral mode:** uploads to your S3-compatible bucket and sends a presigned URL to Mistral
3. **Local Apple mode (macOS 26+):** processes directly on-device without S3/API calls
4. **Delivers** markdown to your clipboard and saves it as a `.md` file
5. **Cleans up** S3 objects automatically after 24 hours (for Mistral jobs)

## Supported File Types

| Category   | Formats                             | Provider options                                               |
| ---------- | ----------------------------------- | -------------------------------------------------------------- |
| **Audio**  | mp3, wav, m4a, ogg, flac, webm, mp4 | Mistral Voxtral Mini Transcribe V2, or Local Apple (macOS 26+) |
| **PDF**    | pdf (scanned & digital)             | Mistral OCR 3, or Local Apple OCR (macOS 26+)                  |
| **Images** | png, jpg, jpeg, heic, tiff, webp    | Mistral OCR 3, or Local Apple OCR (macOS 26+)                  |

## Key Design Principles

- **Per-media provider selection** — audio, PDF, and image each have independent mode selection; modeled as extensible options (not a hardcoded toggle).
- **BYOK (Bring Your Own Key)** — no subscription; when using Mistral mode, you pay Mistral and your S3 provider directly for what you use.
- **Parallel batch processing** — drop multiple files at once; they all process concurrently with per-file progress tracking.
- **Privacy-first** — API keys stored in macOS Keychain, config follows XDG conventions, no telemetry, no analytics.

## Tech Stack

- **Swift 6** with **SwiftUI**, targeting **macOS 14+ (Sonoma)**
- Clean Architecture: domain layer with use cases and gateway protocols, infrastructure layer with concrete implementations (`S3Client`, `MistralAudioProvider`, `MistralOCRProvider`, `AppleSpeechAnalyzerProvider`, `AppleDocumentOCRProvider`, `KeychainStore`, etc.)
- Native `URLSession` for networking, Swift Concurrency (`async/await`, `TaskGroup`) for parallelism

## Install

```bash
brew tap jwa91/tap
brew install --cask trnscrb
```

Requires macOS 14 (Sonoma) or later (For Apple OCR and Audio capabilties macOS 26+ is needed).
