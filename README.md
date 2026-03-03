# trnscrb

A macOS menu bar app that converts audio recordings, PDFs, and images (including handwritten notes) into clean, well-formatted markdown — with a single drag-and-drop gesture.

## How It Works

Drop a file onto the menu bar icon (or into the popover drop zone), and trnscrb handles the rest:

1. **Uploads** the file to your own S3-compatible storage bucket (Hetzner, Cloudflare R2, AWS, etc.)
2. **Sends** a presigned URL to the Mistral API for processing
3. **Delivers** the resulting markdown to your clipboard and/or saves it as a `.md` file
4. **Cleans up** the S3 object automatically after 24 hours

## Supported File Types

| Category | Formats | Mistral Endpoint |
|----------|---------|-----------------|
| **Audio** | mp3, wav, m4a, ogg, flac, webm, mp4 | Voxtral Mini Transcribe V2 — with speaker diarization, up to 3 hrs per file |
| **PDF** | pdf (scanned & digital) | OCR 3 — native markdown output, 2,000 pages/min |
| **Images** | png, jpg, jpeg, heic, tiff, webp | OCR 3 — 88.9% handwriting accuracy |

## Key Design Principles

- **BYOK (Bring Your Own Key)** — no subscription; you pay Mistral and your S3 provider directly for what you use. A single Mistral API key covers all three file types.
- **Zero UI overhead** — the entire interface lives in the menu bar popover. No windows, no onboarding wizard. Settings slide in from a gear icon.
- **Parallel batch processing** — drop multiple files at once; they all process concurrently with per-file progress tracking.
- **Privacy-first** — API keys stored in macOS Keychain, config follows XDG conventions, no telemetry, no analytics.

## Tech Stack

- **Swift 6** with **SwiftUI**, targeting **macOS 14+ (Sonoma)**
- Clean Architecture: domain layer with use cases and gateway protocols, infrastructure layer with concrete implementations (S3Client, MistralAudioProvider, MistralOCRProvider, KeychainStore, etc.)
- Native `URLSession` for networking, Swift Concurrency (`async/await`, `TaskGroup`) for parallelism

## TODO

- [ ] **Homebrew Tap distribution** — publish a Homebrew tap so users can install and update trnscrb via `brew install --cask trnscrb`
- [ ] **Local-only mode (macOS 26+)** — leverage macOS Tahoe's on-device `RecognizeDocumentsRequest` and `SpeechAnalyzer` APIs for fully local, zero-cost transcription and OCR with no API keys or S3 bucket required
