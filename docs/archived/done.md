## 1. DONE. Completed Job Rows Are a Dead End

**Finding:** When a job completes, the row shows `checkmark.circle.fill` + "Done" in `.caption2` green. That's it. There's no visible way to:

- Copy the markdown
- Open the markdown file on disk
- Preview the content
- See the S3 link

The only way to copy is to _click the row_ (undiscoverable) or right-click for a context menu. Neither is communicated visually.

**Recommendations:**

- **A.** Replace the bare "Done" label with actionable inline buttons. Show a small "Copy" button (or `doc.on.doc` icon) and an "Open in Finder" button (`folder` icon). These should appear on hover or always be visible for completed rows.
- **B.** Add a brief toast/confirmation when markdown is copied (e.g. "Copied!" that fades after 1.5s), so the user gets feedback that the tap did something.
- **C.** Show the saved file path (truncated) as a clickable link under the row, or at minimum surface it in the context menu as "Reveal in Finder".
- **D.** Consider a small inline markdown preview on row expansion (disclosure triangle or click-to-expand), showing the first few lines.

## DONE. 2. S3 Upload URL Is Never Surfaced

**Finding:** The `ProcessFileUseCase` generates a presigned S3 URL during upload, but it's only passed to the transcription provider and then discarded. The `Job` entity doesn't store it. The `TranscriptionResult` doesn't include it. The user never sees where their file went.

**Recommendations:**

- **A.** Store the S3 object URL (not presigned, just the path-style URL `endpoint/bucket/key`) on the `Job` entity after upload completes.
- **B.** Add a "Copy S3 Link" option to the context menu of completed jobs.
- **C.** Optionally show the S3 key path as a subtle detail line on the row (like you already do for errors/warnings).
