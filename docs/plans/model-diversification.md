## Revised Research: Specialized Models for trnscrb (March 2026)

### Audio Transcription — Current Leaderboard

Per the [Artificial Analysis AA-WER v2.0 benchmark](https://artificialanalysis.ai/speech-to-text) (released March 1, 2026):

| Rank | Model                          | AA-WER | Notes                                                                           |
| ---- | ------------------------------ | ------ | ------------------------------------------------------------------------------- |
| 1    | **ElevenLabs Scribe v2**       | 2.3%   | Released Jan 2026. 90+ languages. Also has Realtime variant (30-80ms).          |
| 2    | **Google Gemini 3 Pro**        | 2.9%   | Current gen (Gemini 3.1 Pro Preview out Feb 19). Native multimodal.             |
| 3    | **Mistral Voxtral Small**      | 3.0%   | Notably: trnscrb uses Voxtral _Mini_ — upgrading to Small could be a quick win. |
| 4    | **Google Gemini 3 Flash**      | 3.1%   | Cheaper/faster than 3 Pro, nearly as accurate.                                  |
| 5    | **ElevenLabs Scribe v1**       | 3.2%   | Previous gen.                                                                   |
| —    | **Whisper Large v3**           | 4.2%   | Mid-pack, open source baseline.                                                 |
| —    | **AssemblyAI Universal-3 Pro** | —      | 2.3% on AgentTalk (voice-assistant-directed speech).                            |
| —    | **Deepgram Nova-3**            | ~5.3%  | Updated Feb 2026. Unique: self-serve domain fine-tuning. Best latency.          |

**Open source standouts:**

- **NVIDIA Canary Qwen 2.5B** — 5.63% WER, #1 on HuggingFace Open ASR Leaderboard. FastConformer + Qwen3-1.7B decoder.
- **Whale (1.87B)** — 2.4% WER on LibriSpeech clean. 144 languages. w2v-BERT + E-Branchformer. Open weights.
- **IBM Granite Speech 3.3 8B** — ~5.85% average WER.

### OCR / Document Parsing — Current Leaderboard

All models below released in Jan–Feb 2026:

| Model                        | OmniDocBench v1.5 | Size  | Notes                                                                                                                             |
| ---------------------------- | ----------------- | ----- | --------------------------------------------------------------------------------------------------------------------------------- |
| **GLM-OCR** (Zhipu)          | **94.62** (#1)    | 0.9B  | Open source. Feb 2026. Ollama/vLLM/SGLang. Formula + table + info extraction.                                                     |
| **PaddleOCR-VL 1.5** (Baidu) | 94.5              | 0.9B  | Jan 2026. 109 languages. Open source. Strong on reading order, formulas, tables.                                                  |
| **dots.ocr 1.5** (RedNote)   | 87.5 (EN)         | —     | Feb 2026. Multilingual SOTA. Also does scene text and SVG generation.                                                             |
| **OCRFlux-3B** (ChatDOC)     | 0.967 EDS         | 3B    | Cross-page table merging at 98.3%. Runs on consumer GPU (3090). PDF-to-markdown native.                                           |
| **Mistral OCR 3**            | —                 | small | Jan 2026. 74% win rate over OCR 2 (which trnscrb currently uses). Much better on handwriting, forms, tables. $1/1000 pages batch. |
| **olmOCR-2 7B** (AI2)        | 82.4              | 7B    | Strong on old scans, arXiv, multi-column. Open source.                                                                            |

### Recommendations for trnscrb — What Actually Matters

**Immediate / low-effort wins:**

1. **Upgrade Mistral OCR → OCR 3** — You already integrate Mistral. OCR 3 is a drop-in upgrade with 74% win rate over your current model, especially on handwritten notes (a core trnscrb feature). Likely just a model name change in the API call.

2. **Upgrade Voxtral Mini → Voxtral Small** — Same Mistral API, but Voxtral Small scores 3.0% vs Mini's presumably higher WER. Another near-drop-in upgrade.

**New provider additions (high impact):**

3. **ElevenLabs Scribe v2** (audio) — #1 accuracy at 2.3% WER, 90+ languages. Great for users who need the absolute best transcription. Simple REST API.

4. **GLM-OCR** (local OCR) — #1 on OmniDocBench at 94.62, only 0.9B params, runs via Ollama locally. This would be a massive upgrade over Apple Vision as a local OCR option, and it's open source.

5. **Gemini 3 Flash** (audio + OCR) — Current gen (not old!), 3.1% WER for audio AND strong document understanding. One API key covers both audio and document tasks. Cost-effective.

**Specialized / niche:**

6. **OCRFlux-3B** — If users need to process multi-page PDFs with tables that span pages (98.3% cross-page merge accuracy). Unique capability no other model offers well. 3B, runs locally.

7. **Deepgram Nova-3** (audio) — Unique self-serve fine-tuning for domain-specific vocabulary (medical, legal, etc.). Updated Feb 2026.

8. **Gladia** (audio) — Up to 39% more accurate on European languages. Relevant for your Dutch (nl-NL) users.

---

Sources:

- [Artificial Analysis STT Leaderboard](https://artificialanalysis.ai/speech-to-text)
- [ElevenLabs & Google dominate updated STT benchmark](https://the-decoder.com/elevenlabs-and-google-dominate-artificial-analysis-updated-speech-to-text-benchmark/)
- [ElevenLabs Scribe v2](https://elevenlabs.io/blog/introducing-scribe-v2)
- [ElevenLabs Scribe v2 Realtime](https://elevenlabs.io/blog/introducing-scribe-v2-realtime)
- [Mistral OCR 3](https://mistral.ai/news/mistral-ocr-3)
- [GLM-OCR on HuggingFace](https://huggingface.co/zai-org/GLM-OCR)
- [GLM-OCR: 0.9B #1 OmniDocBench](https://stable-learn.com/en/glm-ocr-introduction/)
- [PaddleOCR-VL 1.5 on AMD](https://www.amd.com/en/developer/resources/technical-articles/2026/unlocking-high-performance-document-parsing-of-paddleocr-vl-1-5-.html)
- [dots.ocr 1.5 on HuggingFace](https://huggingface.co/rednote-hilab/dots.ocr-1.5)
- [dots.ocr 1.5 vs GLM-OCR vs PaddleOCR-VL 1.5](https://instavar.com/blog/ai-production-stack/Dots_OCR_1_5_vs_GLM_OCR_vs_PaddleOCR_VL_1_5)
- [OCRFlux-3B on GitHub](https://github.com/chatdoc-com/OCRFlux)
- [Deepgram Nova-3 Feb 2026 update](https://developers.deepgram.com/changelog)
- [Gemini 3.1 Pro Preview](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-1-pro/)
- [NVIDIA Canary Qwen](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
- [Whale ASR](https://arxiv.org/abs/2506.01439)
- [Gladia](https://www.gladia.io/)
