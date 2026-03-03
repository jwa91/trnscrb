# trnscrb — Provider Research (March 2026)

> Research into transcription/OCR services for each media type, covering both cloud (BYOK) and local-only tracks. Evaluation criteria: quality (English primary, Dutch nice-to-have), pricing, API ergonomics, speed, and RAM constraints for local options.

---

## Implementation Status (Current App)

- Per-media provider mode is implemented in settings (`mistral` or `local` for audio/PDF/image).
- Mistral remains the default mode for all media types.
- Local Apple processing path is enabled for macOS 26+ with on-device providers.
- On macOS <26, local mode is not available in settings and processing resolves to Mistral requirements.

---

## Cloud Track — Recommendations

### Audio: Mistral Voxtral Mini Transcribe V2

**Why it wins:**
- **$0.18/hr** — 2x cheaper than OpenAI ($0.36/hr), 2.5x cheaper than Deepgram ($0.46/hr)
- **No chunking needed** — accepts files up to 1 GB / 3 hours in a single request. A 2-hour meeting just works. This eliminates an entire category of complexity (overlap management, speaker-ID stitching, timestamp arithmetic, per-chunk retry logic)
- **Built-in diarization** at no extra cost (Deepgram and AssemblyAI charge extra)
- **~4% WER** on FLEURS — competitive with frontier models
- **Dutch explicitly supported** and benchmarked, outperforms Whisper on European languages
- **OpenAI-compatible API** — straightforward REST integration from Swift
- **European provider** (Paris) — GDPR advantage
- Context biasing (custom vocabulary) and word-level timestamps included

**Runner-up: Groq Whisper Large v3 Turbo** — $0.04/hr (4.5x cheaper), 216x real-time speed. Trade-off: requires chunking (100MB/~25min limit) and no diarization. Good "power user" option.

| Provider | Price/hr | 2hr meeting cost | Chunking needed? | Diarization | Dutch | Max file |
|---|---|---|---|---|---|---|
| **Mistral Voxtral V2** | **$0.18** | **$0.36** | **No** | **Included** | **Yes** | **1 GB / 3hr** |
| Groq Whisper Turbo | $0.04 | $0.08 | Yes (12+ chunks) | No | Yes | 100 MB |
| AssemblyAI Universal | $0.15 | $0.30 | No | Extra cost | Yes | 5 GB / 10hr |
| OpenAI GPT-4o Transcribe | $0.36 | $0.72 | Yes (5+ chunks) | Included | Yes | 25 MB |
| Deepgram Nova-3 | $0.46 | $0.92 | Likely no | Extra cost | Yes | 2 GB |

---

### PDF: Mistral OCR 3

**Why it wins:**
- **$0.002/page** (batch: $0.001/page) — 1.5x cheaper than LlamaParse, 5-15x cheaper than Google/Adobe/Reducto
- **Native markdown output** with HTML tables (colspan/rowspan), headings, lists, LaTeX/math preservation
- **96.6% table accuracy** (vs. Textract 84.8%), **88.9% handwriting accuracy** (vs. Azure 78.2%)
- **2,000 pages/min** processing speed — a 100-page PDF in ~3 seconds
- Simple REST endpoint: `POST /v1/ocr`, Bearer auth, accepts URL/base64/file_id
- **50 MB / 1,000 pages** per request — covers most use cases
- 100+ languages including Dutch
- **European provider** (Paris)

**Runner-up: LlamaParse V2 (Cost Effective)** — $0.003/page with good markdown output. Slightly lower quality but established brand. Free tier of 10,000 credits/month useful for development.

| Provider | Price/page | Markdown output | Table quality | Scanned PDF | Speed | API simplicity |
|---|---|---|---|---|---|---|
| **Mistral OCR 3** | **$0.002** | **Native, excellent** | **96.6%** | **Very good** | **2,000 pg/min** | **Simple REST** |
| LlamaParse V2 | $0.003-$0.09 | Native, good | Good | Good | 6-53s/doc | REST + Python SDK |
| Google Document AI | $0.01 | No (JSON only) | Very good | Very good | Fast | Heavy GCP setup |
| Adobe PDF Extract | ~$0.01 | Native (new) | Very good | Decent | Moderate | OAuth, heavy |
| Reducto | $0.015 | Native, good | Excellent | Very good | Moderate | REST |

---

### Images/OCR: Claude Haiku 4.5 (default) + Gemini 2.5 Flash (budget)

**Why Claude Haiku 4.5 as default:**
- **Best markdown structuring** of any provider — outstanding instruction-following for formatting
- **Sub-200ms response time**, 108 tokens/sec — critical for a menu bar app that should feel instant
- **~$0.003/image** — negligible cost per use
- Excellent API ergonomics (cleanest SDK/REST of any provider)
- Good handwriting recognition; very good printed text

**Why Gemini 2.5 Flash as budget option:**
- **~$0.0004/image** — 7.5x cheaper than Claude Haiku
- Very good OCR quality (near-frontier)
- 248 tokens/sec, 0.46s TTFT
- Strong spatial reasoning (understands layout hierarchy)

**For peak handwriting accuracy:** GPT-5 or Gemini 2.5 Pro lead benchmarks, but Claude's markdown output quality compensates for the marginal character-recognition gap.

**Interesting niche find:** Transkribus has a Dutch-specific model (Demeter Super Model) with 4.9% CER on Dutch handwriting — if Dutch handwriting ever becomes a core feature, this is unmatched.

| Provider | Est. cost/image | Handwriting | Printed OCR | Markdown quality | Speed | API quality |
|---|---|---|---|---|---|---|
| **Claude Haiku 4.5** | **$0.003** | **Good** | **Excellent** | **Outstanding** | **Fast (108 t/s)** | **Excellent** |
| Gemini 2.5 Flash | $0.0004 | Very good | Excellent | Excellent | Very fast (248 t/s) | Good |
| Gemini 2.5 Pro | $0.002 | Excellent | Excellent | Excellent | Moderate | Good |
| Mistral OCR 3 | $0.002/page | Very good (88.9%) | Very good | Good (native) | Fast | Good |
| GPT-4.1 nano | $0.0003 | Good | Good | Good | Fast | Excellent |
| Groq Llama 4 Scout | $0.0003 | Fair | Good | Fair | Fastest (460 t/s) | Good |

---

## Local-Only Track — Recommendations

> Constraint: must work on 8GB MacBook Air with other apps open (~4-5GB available for trnscrb)

### Local Audio: WhisperKit with `small-en`

**Why it wins:**
- **Pure Swift** via SPM — cleanest integration for a native macOS app
- **Core ML / ANE** acceleration — efficient on memory and power
- Apple collaborated with Argmax (WhisperKit's creator) on the macOS 26 SpeechAnalyzer API — this is the endorsed path
- **~200-300 MB runtime** RAM with `small-en` — comfortable on 8GB
- **3.4% English WER** — excellent for meeting transcription
- Models downloaded on demand (no app bundle bloat)
- Load/unload lifecycle: ~20-30 MB idle, loads model only when transcribing

**Runner-up: whisper.cpp via SwiftWhisper** — more mature, explicit memory control via C API, Q5 quantization (~450 MB RAM, ~190 MB disk). Better if you want to bundle the model in-app for fully offline first-launch.

**Future-proof: Apple SpeechAnalyzer (macOS 26+)** — zero model management, zero bundle size, 55% faster than Whisper per Apple's benchmarks, fully managed by the OS. If you target macOS 26+, this becomes the obvious choice.

| Engine | RAM (small model) | English WER | Speed (10min audio, M1 Air) | Swift native? | 8GB safe? |
|---|---|---|---|---|---|
| **WhisperKit small-en** | **~200-300 MB** | **3.4%** | **~1.5 min** | **Yes** | **Yes** |
| whisper.cpp small.en Q5 | ~450 MB | 3.4% | ~1.5 min | Via wrapper | Yes |
| Moonshine v2 medium | ~500 MB | 6.65% | ~1 min | Via SPM | Yes |
| Apple SpeechAnalyzer | System-managed | TBD | ~1.3 min (est.) | Yes | Yes |
| Vosk | ~300 MB | Significantly worse | Fast | Via C API | Yes |
| MLX Whisper | ~450 MB | 3.4% | Fastest | **No (Python)** | Yes |

**Long file handling (1-2hr meetings):** All Whisper-based engines process 30-second windows internally. Pre-chunk to 5-10 min segments, process sequentially. Peak RAM = model + one audio chunk (~10-20 MB). WhisperKit handles this natively.

---

### Local PDF: Apple PDFKit + Vision (Tier 1) + PyMuPDF4LLM (Tier 2)

**The hard constraint eliminates most options.** Docling (4-13GB, memory leaks), Marker (3-5GB), MinerU (10-25GB), and Nougat (academic-only) are all too heavy for 8GB machines.

**Tier 1 — Pure Swift, zero dependencies:**
- **Apple PDFKit** for digital PDF text extraction
- **Apple VNRecognizeTextRequest** for scanned PDF OCR
- Basic structure detection via font-size heuristics (larger = heading)
- **macOS 26+: `RecognizeDocumentsRequest`** returns paragraphs, tables, lists directly — maps almost trivially to markdown
- RAM: ~50-150 MB. Speed: 1-3 sec for 10 pages.

**Tier 2 — Enhanced (optional, Python subprocess):**
- **PyMuPDF4LLM** for better markdown structure (headings, bold, italic, lists, basic tables)
- ~100-300 MB RAM, processes 10 pages in ~1-2 seconds
- No ML models needed (no multi-GB downloads)
- Table accuracy is weak point (struggles without borders)

| Tool | RAM | Speed (10pg) | Markdown output | Scanned PDF | 8GB safe? |
|---|---|---|---|---|---|
| **Apple PDFKit + Vision** | **~50-150 MB** | **1-3 sec** | **macOS 26: structured; older: raw text** | **Very good OCR** | **Yes** |
| PyMuPDF4LLM | ~100-300 MB | 1-2 sec | Good (headings, lists, basic tables) | Needs Tesseract | Yes |
| Docling | 4-13 GB (leaks) | 13-30 sec | Excellent | Good | **No** |
| Marker | 3-5 GB | 40-60 sec CPU | Very good | Good | **No** |
| MinerU | 10-25 GB | Minutes | Very good | Good | **No** |

---

### Local Images/OCR: Apple Vision Framework

**Clear winner — nothing else comes close on 8GB machines.**

- **~50-150 MB transient RAM** — the OS manages model lifecycle
- **100-500ms per image** — effectively instant
- **Native Swift, zero dependencies**, zero binary size overhead
- Full Apple Silicon optimization (Metal + ANE)
- Good handwriting recognition (English), excellent printed text
- **macOS 26: `RecognizeDocumentsRequest`** returns structured paragraphs, tables, lists — game-changer

**Enhanced mode (16GB+ machines, optional):**
- **Qwen2.5-VL 3B 4-bit via MLX Swift** (~3-5 GB RAM) — full image→markdown in one prompt
- **Gemma 3 4B 4-bit via MLX Swift** (~4 GB RAM) — similar capability
- Or use a tiny text-only LLM (Gemma 3 1B, ~1.5 GB) to reformat Apple Vision OCR output into structured markdown

| Tool | RAM | Speed | Handwriting | Markdown output | 8GB safe? |
|---|---|---|---|---|---|
| **Apple Vision** | **~50-150 MB** | **100-500ms** | **Good** | **macOS 26: structured; older: raw text** | **Yes** |
| Qwen2.5-VL 3B (MLX) | ~3-5 GB | 3-8 sec | Good | Prompted | Tight |
| Gemma 3 4B (MLX) | ~4 GB | 3-8 sec | Good | Prompted | Tight |
| Tesseract | ~100-300 MB | 200-500ms | Poor | No | Yes |
| EasyOCR | 500 MB-2 GB (leaks) | 1-3 sec | Moderate | No | Risky |

---

## Summary: Recommended Provider Stack

### Cloud (Primary — BYOK)

| Media | Provider | Price | Key Advantage |
|---|---|---|---|
| **Audio** | Mistral Voxtral Mini V2 | $0.18/hr | No chunking (3hr/1GB), built-in diarization |
| **PDF** | Mistral OCR 3 | $0.002/page | Native markdown, 96.6% tables, 2000 pg/min |
| **Images** | Claude Haiku 4.5 | $0.003/image | Best markdown output, sub-200ms |

**Notable pattern:** Mistral dominates audio + PDF. Both are the same provider (same API key), European, cheapest, and produce excellent output. This simplifies the BYOK experience — users may only need 2 API keys (Mistral + Anthropic) instead of 3.

### Local-Only (Alternative Track)

| Media | Provider | RAM | Key Advantage |
|---|---|---|---|
| **Audio** | WhisperKit (small-en) | ~200-300 MB | Pure Swift, 3.4% WER, ANE-accelerated |
| **PDF** | Apple PDFKit + Vision | ~50-150 MB | Zero dependencies, macOS 26 structured output |
| **Images** | Apple Vision | ~50-150 MB | 100-500ms, zero dependencies |

**Total local RAM budget:** ~400-600 MB peak (processing one file at a time). Comfortably fits on 8GB.

**Key macOS 26 (Tahoe) opportunity:** Both `RecognizeDocumentsRequest` (structured document output) and `SpeechAnalyzer` (native Whisper-level STT) are new in macOS 26. If you target Tahoe as the minimum, the local track becomes significantly simpler and higher quality with zero bundled dependencies.

---

## Open Decisions

1. **Minimum macOS version** — targeting macOS 26 (Tahoe) unlocks `RecognizeDocumentsRequest` + `SpeechAnalyzer`, dramatically simplifying the local track. Targeting macOS 14+ means using older Vision APIs and WhisperKit/whisper.cpp for audio.

2. **Mistral for both audio + PDF?** — Using Mistral for two out of three media types simplifies BYOK (one key for audio+PDF, one for images). But it creates provider concentration risk. Consider offering alternatives.

3. **Local-only as a mode or a separate app?** — The local track works well enough for a "lite mode" (no API keys needed, lower quality). Could be the default with cloud as "enhanced mode," or vice versa.

4. **Audio provider final call** — Mistral Voxtral is the recommendation, but Groq Whisper Turbo at $0.04/hr is compelling if users want the cheapest option and you implement chunking.

---

## Sources

Full source lists are available in the individual research transcripts. Key references:

**Audio:** [Mistral Voxtral 2](https://mistral.ai/news/voxtral-transcribe-2), [Groq Pricing](https://groq.com/pricing), [Deepgram Nova-3](https://deepgram.com/learn/introducing-nova-3-speech-to-text-api), [AssemblyAI Pricing](https://www.assemblyai.com/pricing), [OpenAI Pricing](https://openai.com/api/pricing/)

**PDF:** [Mistral OCR 3](https://mistral.ai/news/mistral-ocr-3), [LlamaParse Pricing](https://www.llamaindex.ai/pricing), [Reducto vs LlamaParse](https://llms.reducto.ai/reducto-vs-llamaparse), [Adobe PDF Extract](https://developer.adobe.com/document-services/docs/overview/pdf-extract-api/)

**Images/OCR:** [Claude Vision Docs](https://platform.claude.com/docs/en/build-with-claude/vision), [Gemini Pricing](https://ai.google.dev/gemini-api/docs/pricing), [OCR Arena Leaderboard](https://www.ocrarena.ai/leaderboard), [Mistral OCR Docs](https://docs.mistral.ai/capabilities/document_ai/basic_ocr)

**Local Audio:** [WhisperKit](https://github.com/argmaxinc/WhisperKit), [whisper.cpp](https://github.com/ggml-org/whisper.cpp), [Moonshine v2](https://github.com/moonshine-ai/moonshine), [Apple SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)

**Local PDF:** [Docling](https://github.com/docling-project/docling), [PyMuPDF4LLM](https://pymupdf.readthedocs.io/en/latest/pymupdf4llm/), [marker](https://github.com/datalab-to/marker)

**Local Images:** [Apple Vision](https://developer.apple.com/documentation/vision/vnrecognizetextrequest), [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest), [MLX-VLM](https://dzone.com/articles/vision-ai-apple-silicon-guide-mlx-vlm)
