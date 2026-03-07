# trnscrb Product Model

> Brief framing for product scope, positioning, and configuration.

## Core Promise

trnscrb is the frictionless capture layer for AI and knowledge workflows. It turns unstructured media into consistent markdown, quickly and reliably.

It is not a general AI wrapper. It sits earlier in the pipeline: capture, normalize, deliver.

## Two Independent Concerns

### 1. Processing

This decides where transcription or OCR happens.

- `Local`: process on-device
- `Cloud`: process with a remote provider

### 2. Pipeline Options

These are optional workflow steps around the source file and output.

The first power-user pipeline feature is:

- `Bucket Mirroring`: mirror the original file to S3-compatible object storage for staging, archival, or later downstream automation

Bucket mirroring is independent from processing. It can be enabled for both local and cloud processing.

## Supported Combinations

- `Local` + no bucket mirroring: fastest, simplest, privacy-first
- `Local` + bucket mirroring: local markdown plus source-file mirroring for advanced workflows
- `Cloud` + no bucket mirroring: simplest cloud-quality path
- `Cloud` + bucket mirroring: cloud processing plus durable source-file mirroring

## Product Implications

- First-run setup should not require S3
- S3 should be framed as an advanced pipeline capability, not the core product
- Processing should remain functional without bucket mirroring
- Bucket mirroring should default to optional mirroring, not a required precondition for processing
- Near-term product work should prioritize robustness and quality of the core local and cloud pipelines

## User-Facing Language

Prefer:

- `Processing`: Local / Cloud
- `Advanced Pipeline`
- `Mirror originals to S3`
- `Retention`
- `Path Prefix`

Avoid making S3 sound like the app's primary identity or mandatory transport layer.
