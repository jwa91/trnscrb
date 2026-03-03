# trnscrb

> A macOS menu bar app that converts audio recordings, PDFs, and images (including handwritten notes) into clean, well-formatted markdown. Drop a file onto the menu bar icon, and get markdown back — copied to your clipboard or saved as a `.md` file. Built on a BYOK (bring your own API key) model with S3-compatible storage as the intermediary. Inspired by [BucketDrop](https://github.com/fayazara/bucketdrop).

## Goals

- Convert audio, PDFs, and images to markdown with a single drag-and-drop gesture
- Feel instant: the app should never make the user wait for UI — processing happens in the background
- Zero learning curve: drop a file, get markdown. No onboarding flow, no wizard, no tutorial
- Affordable to operate: BYOK model means no subscription, users pay only for what they use
- Multilingual support out of the box, with strong Dutch language quality

## User Stories

- As a user, I want to drag an audio recording onto the menu bar icon so that I get a markdown transcription without opening any app
- As a user, I want to drag a PDF (scanned or digital) onto the icon so that I get the contents as structured markdown
- As a user, I want to drag a photo of handwritten notes onto the icon so that I get the text recognized and formatted as markdown
- As a user, I want to drop multiple files at once so that they all process in parallel and I get results as each completes
- As a user, I want to choose between clipboard delivery and file-save delivery so that the output fits my workflow
- As a user, I want to configure my own S3 bucket and API key so that I control my data and costs
- As a user, I want to see processing progress in the menu bar popover so that I know what's happening without a separate window

## Core Features

### Drag-and-Drop File Ingestion

The menu bar icon accepts files via drag-and-drop. Supported input types:

**Audio:** `.mp3`, `.wav`, `.m4a`, `.ogg`, `.flac`, `.webm`, `.mp4` (audio track)
**PDF:** `.pdf` (scanned and digital)
**Images:** `.png`, `.jpg`, `.jpeg`, `.heic`, `.tiff`, `.webp`

The app detects the file type and routes it to the appropriate processing pipeline. Unsupported file types show a brief error notification ("Unsupported file type: .xyz").

### S3 Upload Pipeline

This pipeline is used when the selected provider mode for a media type is `Mistral`.

1. User drops file onto menu bar icon
2. File is uploaded to the user's configured S3-compatible bucket
3. The S3 object URL (presigned) is passed to the Mistral API
4. After successful processing, the S3 object is marked for deletion (retained ~24 hours as a safety net for retries, then auto-cleaned)

Mistral's APIs accept external URLs directly: the audio endpoint has a `file_url` parameter, and the OCR endpoint accepts any accessible URL via `DocumentURLChunk` / `ImageURLChunk`. This means the app generates a presigned S3 URL and passes it straight to Mistral — no download-then-reupload zigzag.

Upload supports any S3-compatible provider: Hetzner Object Storage, Cloudflare R2, AWS S3, MinIO, Backblaze B2, etc. Configuration follows BucketDrop's pattern — user provides endpoint URL, access key, secret key, and bucket name.

### Transcription & OCR Processing

Each media type has an independent provider mode:

- `Mistral` (cloud path, S3 + API key required)
- `Local Apple` (on-device path, macOS 26+)

Routing is resolved by `(file type, selected mode, OS availability)`. On macOS <26, local mode is unavailable in settings and processing falls back to Mistral requirements if a local value is forced via manual config edits.

The cloud provider remains Mistral (single key) based on benchmarking across quality, pricing, speed, API ergonomics, and multilingual support (see `RESEARCH.md`).

**Why Mistral for everything:**

- Single API key covers all three media types — simplest possible BYOK experience
- European provider (Paris) — GDPR-friendly, aligns with preference for European services
- Competitive pricing across all three types
- All APIs return markdown natively or near-natively
- Dutch is explicitly supported across audio and OCR

#### Audio: Mistral Voxtral Mini Transcribe V2

Endpoint: `POST /v1/audio/transcriptions`

- **$0.18/hr** ($0.003/min) — a 2-hour meeting costs $0.36
- Accepts files up to **1 GB / 3 hours** in a single request — no chunking needed for meetings or lectures. This eliminates the complexity of overlap management, speaker-ID stitching across chunks, timestamp arithmetic, and per-chunk retry logic.
- Built-in **speaker diarization** at no extra cost — identifies who said what
- **~4% WER** on FLEURS benchmark, with Dutch explicitly supported and benchmarked
- Context biasing (custom vocabulary) and word-level timestamps included
- OpenAI-compatible API format — straightforward REST integration from Swift

#### PDF: Mistral OCR 3

Endpoint: `POST /v1/ocr` with `DocumentURLChunk`

- **$0.002/page** (batch: $0.001/page) — a 100-page PDF costs $0.20
- **Native markdown output** with HTML tables supporting colspan/rowspan, headings, lists, and LaTeX/math preservation
- **96.6% table accuracy** (vs. AWS Textract 84.8%), **88.9% handwriting accuracy** (vs. Azure 78.2%)
- Processes at **2,000 pages/min** — a 100-page document in ~3 seconds
- Handles both scanned and digital PDFs
- **50 MB / 1,000 pages** per request — covers most documents. For larger PDFs, split into batches.

#### Images/OCR: Mistral OCR 3

Endpoint: `POST /v1/ocr` with `ImageURLChunk`

- Same endpoint and pricing as PDF — **$0.002/image**
- Accepts PNG, JPG, AVIF and other common image formats
- 88.9% handwriting accuracy — good for handwritten notes, though not the absolute leader (Claude and Gemini edge it on structured markdown output from handwriting)
- Returns markdown natively — no post-processing needed for most use cases
- For v1, this is a pragmatic choice: slightly below the best-in-class for image OCR, but the single-API-key simplification is worth the tradeoff

### Markdown Delivery

Two output modes, configurable in settings (both can be enabled simultaneously):

**1. Clipboard + Notification (default)**

- Markdown is copied to the system clipboard as soon as processing completes
- A macOS notification appears: "trnscrb: [filename] ready — copied to clipboard"
- Clicking the notification opens the popover showing the result

**2. Save to folder**

- Markdown is written as a `.md` file to a user-configured output folder
- Filename follows the pattern: `{original_name}.md` (e.g., `meeting-recording.mp3` → `meeting-recording.md`)
- If a file with that name exists, append a timestamp suffix: `meeting-recording-20260301-1423.md`
- Notification appears: "trnscrb: [filename] saved to [folder]"

### Progress & Status UI

The entire UI lives in the menu bar popover — no separate windows.

**Menu bar icon states:**

- **Idle:** Static icon (a simple, recognizable glyph — e.g., a minimal transcription/document symbol)
- **Processing:** Subtle animation (pulse or spinner overlay) indicating active work
- **Error:** Icon shows a small warning badge until the user acknowledges it

**Popover contents:**

- **Drop zone:** Visible when no jobs are active. "Drop files here or drag onto the icon." Also serves as a click-to-select file picker as a fallback.
- **Job list:** When files are processing, shows a compact list:
  - File name (truncated if long)
  - File type icon (audio/pdf/image)
  - Status: uploading → processing → done / error
  - Progress indicator (determinate if the API supports it, indeterminate otherwise)
- **Completed jobs:** Recent results (last ~10) shown below the active jobs. Clicking a completed job copies its markdown to clipboard.
- **Settings access:** Gear icon in the popover footer opens the settings view within the same popover (sliding panel or tab).

### Settings

Settings are accessible via the popover (gear icon). The popover slides to a settings panel — no separate window.

**Settings are persisted to a config file** following the XDG Base Directory Specification:

- Config path: `$XDG_CONFIG_HOME/trnscrb/config.toml` (defaults to `~/.config/trnscrb/config.toml`)
- The UI reads from and writes to this file

**API keys are NOT stored in the config file.** They are stored in the macOS Keychain and managed exclusively through the settings UI.

**Configurable settings:**

| Setting              | Type                     | Default                       |
| -------------------- | ------------------------ | ----------------------------- |
| S3 endpoint URL      | string                   | — (required)                  |
| S3 access key        | string                   | — (required)                  |
| S3 secret key        | string (Keychain)        | — (required)                  |
| S3 bucket name       | string                   | — (required)                  |
| S3 region            | string                   | `auto`                        |
| S3 path prefix       | string                   | `trnscrb/`                    |
| Mistral API key      | string (Keychain)        | — (required for Mistral mode) |
| Audio provider mode  | enum (`mistral`/`local`) | `mistral`                     |
| PDF provider mode    | enum (`mistral`/`local`) | `mistral`                     |
| Image provider mode  | enum (`mistral`/`local`) | `mistral`                     |
| Output mode          | enum                     | `clipboard`                   |
| Save folder path     | string                   | `~/Documents/trnscrb/`        |
| File retention hours | int                      | `24`                          |
| Launch at login      | bool                     | `false`                       |

Note: when any media type is configured to `mistral`, one Mistral API key is shared across all cloud processing.

## Technical Architecture

### Stack

- **Language:** Swift
- **UI framework:** SwiftUI
- **Target:** macOS 14.0 (Sonoma) or later
- **Architecture pattern:** Follow BucketDrop's structure as a reference
- **Networking:** Native `URLSession` for S3 uploads and Mistral API calls (REST)
- **Storage:** macOS Keychain for secrets, XDG-compliant TOML config file for preferences
- **Concurrency:** Swift Concurrency (`async`/`await`, `TaskGroup` for parallel batch processing)

### Data Flow

```
┌──────────────┐
│  Drop file   │
│  on icon     │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Resolve mode │─── local + macOS26+ ──▶ Local Apple provider ───┐
│ per filetype │                                                 │
└──────┬───────┘                                                 ▼
       │                                                ┌──────────────┐
       └─── mistral / local unsupported ─▶ Upload S3 ─▶ │ Call Mistral │
                                                        └──────┬───────┘
                                                               ▼
                                                         Deliver markdown
```

### Key Components

| Component                                     | Responsibility                                                                 |
| --------------------------------------------- | ------------------------------------------------------------------------------ |
| `AppDelegate` / `MenuBarManager`              | Menu bar icon lifecycle, drop target registration, popover management          |
| `DropZoneView`                                | SwiftUI drag-and-drop surface, file type validation                            |
| `S3Client`                                    | Generic S3-compatible upload/delete using endpoint + credentials from settings |
| `ProcessFileUseCase` + `TranscriptionRouting` | Resolves provider by file type + mode + OS availability                        |
| `MistralAudioProvider`                        | Calls Voxtral transcription endpoint, returns markdown                         |
| `MistralOCRProvider`                          | Calls OCR 3 endpoint for both PDFs and images, returns markdown                |
| `AppleSpeechAnalyzerProvider`                 | Local Apple audio transcription provider (macOS 26+)                           |
| `AppleDocumentOCRProvider`                    | Local Apple OCR provider for PDFs/images (macOS 26+)                           |
| `CompositeDelivery`                           | Clipboard copy, file save, notification dispatch                               |
| `TOMLConfigManager`                           | Reads/writes TOML config, interfaces with Keychain for secrets                 |
| `RetentionCleaner`                            | Background task that deletes expired S3 objects after retention period         |

### Provider Abstraction

Each processor conforms to a shared `TranscriptionGateway` protocol:

```swift
protocol TranscriptionGateway {
    var providerMode: ProviderMode { get }
    var sourceKind: TranscriptionSourceKind { get }
    var supportedExtensions: Set<String> { get }
    func process(sourceURL: URL) async throws -> String
}
```

Current concrete implementations:

- `MistralAudioProvider`
- `MistralOCRProvider`
- `AppleSpeechAnalyzerProvider`
- `AppleDocumentOCRProvider`

This keeps provider addition additive: new mode + new provider registration + routing tests.

## Error Handling

| Scenario                         | Behavior                                                                                                      |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| S3 upload fails                  | Retry up to 3 times with exponential backoff. If all retries fail, show error in popover and notification.    |
| Mistral API fails                | Retry once. On second failure, show error with the API's error message. S3 file is retained for manual retry. |
| Mistral API timeout              | Generous timeout (5 min for audio, 2 min for PDF/image). On timeout, treat as failure and allow retry.        |
| Unsupported file type            | Immediate rejection with notification. No upload attempted.                                                   |
| Mistral credentials missing      | Prompt only when at least one media mode currently resolves to Mistral.                                       |
| Local mode selected on macOS <26 | Settings keeps local mode disabled; runtime falls back to Mistral requirements if needed.                     |
| Network offline                  | Detect before upload attempt. Queue the file and process when connectivity returns.                           |

## Security & Privacy

- **API key** stored exclusively in macOS Keychain — never written to disk in plaintext, never in the config TOML
- **S3 credentials** (secret key) also in Keychain; endpoint, bucket, and access key in config
- All API calls use HTTPS
- S3 uploads use presigned URLs or direct authenticated PUT — no public bucket access required
- Files are auto-deleted from S3 after the configurable retention period
- No telemetry, no analytics, no phoning home — the app is fully local except for the user's own configured services
- App Sandbox entitlements: network access, file system read (for dropped files), Keychain access

## MVP Scope (v1)

- Menu bar app with drag-and-drop onto icon and into popover drop zone
- Per-media provider selection in settings (`Mistral` or `Local Apple`)
- S3-compatible upload with configurable endpoint/credentials (for Mistral mode)
- Mistral processing path (single API key):
  - Audio → Voxtral Mini Transcribe V2 (with diarization)
  - PDF → OCR 3 (scanned and digital)
  - Images → OCR 3 (handwritten and printed)
- Local Apple processing path (macOS 26+):
  - Audio → on-device speech transcription
  - PDF / Images → Apple OCR pipeline
- Clipboard delivery with macOS notification
- Save-to-folder delivery with configurable path
- Per-file progress tracking in popover
- Parallel batch processing
- Settings UI in popover (S3 config, Mistral API key, per-media provider modes, output preferences)
- XDG-compliant config file + Keychain for secrets
- 24-hour S3 retention with auto-cleanup
- Recent results history in popover (~10 items)

## Future Concerns

These are not planned or scoped — just directions to explore after the current baseline is stable.

- **Groq provider:** Groq offers Whisper Turbo ($0.04/hr, fastest inference) and Llama 4 Scout/Maverick (vision, 460 tok/sec). Attractive as a speed-focused or budget alternative. Also uses OpenAI-compatible API format.
- **Ollama support:** Allow users to point trnscrb at a local Ollama instance for fully local processing with their own models. Lightweight integration — just an HTTP endpoint to configure. No bundled Python or models in trnscrb itself.
- **Open-source release and public distribution** (Homebrew cask, DMG)
- **Third provider option per file type** in settings (current model is extensible)
- **Keyboard shortcut** to trigger file picker
- **URL input** (paste a URL to a PDF/audio file instead of dropping a local file)
- **Speaker diarization display** — Voxtral already returns diarization data in v1; a future UI could render speaker-labeled markdown (e.g., `**Speaker 1:** ...`)

## Resolved Questions

These were open during the research phase and are now decided. See `RESEARCH.md` for the full evaluation behind each decision.

- **Mode strategy:** per-media provider choice in settings with `mistral` as default and `local` as Tahoe-only option.
- **Audio provider:** Mistral Voxtral Mini Transcribe V2. Chosen over Groq Whisper ($0.04/hr but requires chunking and lacks diarization), OpenAI GPT-4o Transcribe ($0.36/hr), and Deepgram Nova-3 ($0.46/hr). Key advantage: 3-hour / 1 GB files with no chunking eliminates an entire category of complexity.
- **PDF provider:** Mistral OCR 3. Chosen over LlamaParse ($0.003/page, good but slower), Google Document AI (no markdown output, heavy GCP setup), and Adobe PDF Extract (opaque pricing, OAuth). Key advantage: native markdown output at $0.002/page with 2,000 pages/min.
- **Image/OCR provider:** Mistral OCR 3. A pragmatic v1 choice — Claude Haiku 4.5 and Gemini 2.5 Flash produce better structured markdown from handwriting, but using the same API for all three types (one key, one billing dashboard) outweighs the quality delta for v1.
- **Markdown quality / post-processing:** Not needed for v1. Voxtral returns well-structured transcript text with diarization and timestamps. OCR 3 returns native markdown with headings, tables, and lists. Both are usable as-is without an LLM post-processing pass.
- **Audio chunking strategy:** Not needed. Voxtral accepts up to 3 hours / 1 GB per request. No chunking, stitching, or overlap logic required.
- **S3 presigned URLs with Mistral:** Confirmed to work. Mistral's audio endpoint accepts `file_url` (any accessible URL), and the OCR endpoint accepts URLs via `DocumentURLChunk` / `ImageURLChunk`. The docs state "be sure the URL is public and accessible by our API" — a presigned S3 URL satisfies this. The pipeline is clean: upload to S3 → generate presigned URL → pass URL to Mistral. No intermediary upload to Mistral's own storage needed.
- **Supabase Storage as S3 endpoint:** Not pursued for v1. Supabase Storage uses S3 under the hood but its client API differs from standard S3. The simpler path is to use a direct S3-compatible provider (e.g., Hetzner Object Storage at `nbg1.your-objectstorage.com`). Supabase could be investigated later if demand arises.

## Open Questions

None at this time. Implementation can begin.
