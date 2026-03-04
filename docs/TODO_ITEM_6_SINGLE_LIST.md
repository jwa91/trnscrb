# TODO: Item 6 - One Stable Row Per File

## Goal

Replace the current `ACTIVE` / `RECENT` split with one stable, insertion-ordered list where each file stays in the same row while its state changes.

## What To Change

- Remove the separate `activeJobs` / `completedJobs` rendering split from the popover list UI.
- Render rows from one display list in original insertion order.
- Keep each row in place as it moves through:
  - `pending`
  - `uploading`
  - `processing`
  - `completed`
  - `failed`
- Show progress/status inside the row instead of moving files between sections.
- Remove the `RECENT` header and its `Clear All` button as part of the single-stream layout.

## Row Expectations

- Pending: clear queued/waiting state.
- Uploading: determinate upload progress.
- Processing: clear in-progress transcribing/OCR state.
- Completed: compact action strip remains visible.
- Failed: failure text remains visible with delete action.

## Files Likely Involved

- `trnscrb/Presentation/Popover/JobListView.swift`
- `trnscrb/Presentation/Popover/JobRowView.swift`
- `trnscrb/Presentation/Popover/JobRowPresentation.swift`
- `trnscrb/Presentation/ViewModels/JobListViewModel.swift`
- `Tests/Presentation/JobListViewModelTests.swift`

## Verification

- Multi-file batch keeps rows stable in place while statuses change.
- No row jumps from one section to another.
- Insertion order is preserved.
- `swift test` passes.
