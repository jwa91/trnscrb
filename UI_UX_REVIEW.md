# trnscrb UI/UX Review: Findings & Recommendations

## 1. Completed Job Rows Are a Dead End

**Finding:** When a job completes, the row shows `checkmark.circle.fill` + "Done" in `.caption2` green. That's it. There's no visible way to:
- Copy the markdown
- Open the markdown file on disk
- Preview the content
- See the S3 link

The only way to copy is to *click the row* (undiscoverable) or right-click for a context menu. Neither is communicated visually.

**Recommendations:**
- **A.** Replace the bare "Done" label with actionable inline buttons. Show a small "Copy" button (or `doc.on.doc` icon) and an "Open in Finder" button (`folder` icon). These should appear on hover or always be visible for completed rows.
- **B.** Add a brief toast/confirmation when markdown is copied (e.g. "Copied!" that fades after 1.5s), so the user gets feedback that the tap did something.
- **C.** Show the saved file path (truncated) as a clickable link under the row, or at minimum surface it in the context menu as "Reveal in Finder".
- **D.** Consider a small inline markdown preview on row expansion (disclosure triangle or click-to-expand), showing the first few lines.

## 2. S3 Upload URL Is Never Surfaced

**Finding:** The `ProcessFileUseCase` generates a presigned S3 URL during upload, but it's only passed to the transcription provider and then discarded. The `Job` entity doesn't store it. The `TranscriptionResult` doesn't include it. The user never sees where their file went.

**Recommendations:**
- **A.** Store the S3 object URL (not presigned, just the path-style URL `endpoint/bucket/key`) on the `Job` entity after upload completes.
- **B.** Add a "Copy S3 Link" option to the context menu of completed jobs.
- **C.** Optionally show the S3 key path as a subtle detail line on the row (like you already do for errors/warnings).

## 3. The File List Is Cramped

**Finding:** The entire popover is 320x480. The job list shares this with the drop zone, banners, a divider, and the footer. Each `JobRowView` uses `.caption` for the filename and `.caption2` for status — this is the smallest text macOS offers. Rows have only 4pt vertical padding. With the compact drop zone, banner, and footer all eating space, you get maybe 6-7 visible rows before scrolling.

**Recommendations:**
- **A.** Increase popover width to 360-400pt. Menu bar popovers on macOS commonly go up to 400pt (see 1Password, Bartender, iStatMenus).
- **B.** Bump row typography: use `.body` or `.callout` for filenames, `.caption` for status. The current `.caption` for filenames makes them hard to scan.
- **C.** Increase row vertical padding from 4pt to 8pt for better tap targets and visual breathing room.
- **D.** Consider making the popover height dynamic (clamped to a range like 300-600pt) based on content, rather than fixed at 480.

## 4. Cursors Never Change — Nothing Feels Clickable

**Finding:** No `.onHover` or `.cursor()` modifiers are used anywhere. On macOS, the pointer remains a standard arrow over all interactive elements — buttons, rows, the drop zone, links. This violates macOS HIG which states interactive elements should provide hover feedback.

**Recommendations:**
- **A.** Add `.onHover` with `NSCursor.pointingHand.push()`/`.pop()` on all clickable rows in the job list.
- **B.** Add hover background highlight on rows (e.g. `.background(isHovered ? Color.primary.opacity(0.04) : .clear)`). Currently only the *selected* row gets a background.
- **C.** Add hover state to the drop zone — not just the dashed border on drag, but a subtle background tint when the mouse hovers over it even without a drag.
- **D.** The gear icon in the footer should get a hover highlight (background circle or opacity change).
- **E.** "Choose Files..." and "Clear All" buttons are `.borderless` which renders them as plain text — add hover underline or tint change.

## 5. Inconsistent Action Button Placement Between Views

**Finding:**
- **Main view:** The only action button (gear) is bottom-right in the footer, below a divider.
- **Settings view:** Action buttons are in the header — back button top-left, save button top-right.
- The banner has its own "Settings" button inline with the message.
- "Clear All" lives in a section header.
- "Choose Files..." lives inside the drop zone.
- "Test" buttons are inline with form fields.

There's no consistent pattern for where primary and secondary actions live.

**Recommendations:**
- **A.** Establish a consistent toolbar/header bar pattern for *both* views. The main view should also have a top header bar (e.g. "trnscrb" title left, gear icon right) instead of burying the gear in the footer.
- **B.** Move the gear icon from footer to a header bar, consistent with the settings view having its back/save buttons in the header.
- **C.** The footer area could then be used for a persistent "Add Files" button or drop zone affordance, which is more useful than a gear icon.
- **D.** Per Apple HIG: primary actions should be in a consistent, predictable location. Consider a toolbar-style strip at the top of the popover.

## 6. Wrong Icon for "Add More Files"

**Finding:** The compact drop zone uses `arrow.down.doc` — an arrow pointing *down into* a document. This reads as "download" (import/receive), not "upload" (send files for processing). The same icon is used in the full drop zone, where it makes slightly more sense as "drop files here (downward)", but in compact mode with "Add more files" label, it's confusing.

**Recommendations:**
- **A.** Use `plus.circle` or `plus.rectangle.on.folder` for the compact "Add more files" affordance — it communicates "add" not "download".
- **B.** For the full drop zone, `arrow.down.doc` is acceptable since it communicates "drop here", but consider `square.and.arrow.down` which is the standard macOS "receive/import" symbol.
- **C.** For the menu bar: `doc.text` is fine as the resting state, but `arrow.down.doc.fill` on drag hover could be `plus.circle.fill` or `tray.and.arrow.down.fill` instead.

## 7. Settings: Save Folder Uses a Raw Text Field Instead of Folder Picker

**Finding:** `SettingsView.outputSection` has a plain `TextField("Save Folder", text:)` for the save path. Users must manually type `~/Documents/trnscrb/` or similar. There's no folder picker button, no path validation, no "Browse..." affordance.

**Recommendations:**
- **A.** Add a "Browse..." button next to the text field that opens `NSOpenPanel` configured for directory selection (`canChooseDirectories = true, canChooseFiles = false`).
- **B.** Validate the path on save and show inline feedback if the folder doesn't exist or isn't writable.
- **C.** Show the resolved/expanded path below the field (e.g. resolving `~` to `/Users/jw/...`) so the user knows exactly where files go.
- **D.** Per Apple HIG: always use system-provided pickers for file/folder selection. Manual path entry is an anti-pattern on macOS.

## 8. Settings Form: "Save" Button Is Easy to Miss / No Dirty State Indicator

**Finding:** The Save button is `.borderedProminent` (good) but `.controlSize(.small)` (bad — tiny hit target). There's no indication of unsaved changes. If you change 5 fields and accidentally hit "Back", all changes are lost silently.

**Recommendations:**
- **A.** Track dirty state — compare current values against loaded values. Show a dot/badge on the Save button or change its label to "Save Changes" when dirty.
- **B.** If the user hits Back with unsaved changes, show a confirmation dialog ("You have unsaved changes. Discard?").
- **C.** Increase Save button to `.controlSize(.regular)` — the small size makes it feel secondary when it's actually the primary action.
- **D.** Consider auto-saving individual fields on change (like System Settings does) instead of a manual Save flow — more native-feeling on macOS.

## 9. No Visual Hierarchy in the Job List

**Finding:** Active and completed jobs are separated by section headers ("ACTIVE" / "RECENT"), but the visual distinction is minimal — same row height, same font sizes, same icon treatment. A processing job looks nearly identical to a completed job except for the tiny status indicator.

**Recommendations:**
- **A.** Give active jobs more visual weight: slightly larger row, bolder filename, or a subtle animated accent (pulsing dot, animated progress ring).
- **B.** Dim completed jobs slightly (reduce opacity of the filename to `.secondary`) to create a clear active-vs-done hierarchy.
- **C.** Use a more prominent progress indicator for uploading — the 40pt-wide `ProgressView` is barely visible. Consider a full-width progress bar under the row, or a circular progress ring replacing the file type icon during upload.
- **D.** Failed jobs should stand out more — consider a red-tinted background row, not just red status text.

## 10. No Empty State for the Completed Section

**Finding:** When all completed jobs are cleared or haven't happened yet, there's no message in the list area. The app jumps between full drop zone → compact drop zone + list → hidden drop zone + list based on `PopoverContentLayout`. But there's no "No recent files" or onboarding hint.

**Recommendations:**
- **A.** When the app first launches (no jobs ever), the full drop zone is fine. But after clearing completed jobs, show a subtle "No recent transcriptions" placeholder instead of just the compact drop zone with empty space.
- **B.** Consider a first-run onboarding state that highlights the three input methods (drop zone, menu bar drag, Choose Files button).

## 11. Drop Zone Disappears When Jobs Are Active

**Finding:** `PopoverContentLayout` hides the drop zone entirely when `activeJobCount > 0`. This means while a file is processing, you can't queue more files through the visible drop zone — you'd have to know to drag to the menu bar icon or use the whole-popover drop target (which has zero visual affordance).

**Recommendations:**
- **A.** Always show at least the compact drop zone, even during active processing. Space is tight, but a single-line "Drop or choose more files" bar is only ~40pt tall.
- **B.** If hiding is necessary for space, add a floating "+" button in the footer or header that opens the file picker directly.
- **C.** At minimum, show a tooltip or hint that the entire popover surface accepts drops.

## 12. Context Menu Is the Only Way to Delete

**Finding:** Individual jobs can only be deleted via right-click context menu or the Delete keyboard shortcut. There's no visible delete button. "Clear All" only applies to completed jobs.

**Recommendations:**
- **A.** Add a swipe-to-delete gesture on rows (standard macOS/iOS pattern).
- **B.** Show a trash icon on row hover for direct deletion.
- **C.** Add "Retry" to the context menu for failed jobs, rather than requiring delete + re-drop.

## 13. The "Choose Files..." Button Doesn't Look Like a Button

**Finding:** `chooseFilesButton` uses `.buttonStyle(.borderless)` + `.font(.caption)`. It renders as tiny plain blue text. In the compact mode, "Choose..." is even smaller. This is the *primary alternative* to drag-and-drop and it looks like a footnote.

**Recommendations:**
- **A.** In full mode: make "Choose Files..." a `.borderedProminent` or at least `.bordered` button with regular size. This is the primary CTA when the app is idle.
- **B.** In compact mode: "Choose..." should at minimum be `.bordered` so it has a visible button shape.
- **C.** Per Apple HIG: if you want the user to take an action, the button needs to look like a button. `.borderless` buttons are for supplementary actions.

## 14. No Keyboard Navigation in the Job List

**Finding:** The job list doesn't support arrow key navigation. There's `.onDeleteCommand` for the delete key, but no up/down arrow handling, no Enter to copy, no Cmd+C shortcut.

**Recommendations:**
- **A.** Add up/down arrow key support to navigate between jobs.
- **B.** Add Enter or Cmd+C to copy the selected job's markdown.
- **C.** Add Cmd+A to select all (for bulk operations).
- **D.** Consider using `List` with selection binding instead of `ScrollView` + `VStack` — this gets you keyboard nav and accessibility for free.

## 15. Notification Text Is Vague

**Finding:** Success notification says "ready — copied or saved based on your settings." The user has to remember their settings to know what happened.

**Recommendations:**
- **A.** Be specific: "Copied to clipboard" or "Saved to ~/Documents/trnscrb/file.md" or "Copied to clipboard and saved to folder".
- **B.** Make the notification actionable — clicking should not just open the popover, but also open the saved file if it exists.

## 16. No Accessibility Labels on Status Indicators

**Finding:** Status icons like `checkmark.circle.fill` and `exclamationmark.triangle.fill` don't have explicit accessibility labels. VoiceOver users would hear the SF Symbol name, not the semantic meaning.

**Recommendations:**
- **A.** Add `.accessibilityLabel("Completed successfully")`, `.accessibilityLabel("Failed")`, etc. to all status indicators.
- **B.** Make the entire row announce its full state: "interview.mp3, completed, done" or "photo.png, uploading, 45 percent".

## 17. Settings Test Buttons Have Unclear Scope

**Finding:** "Test" buttons for S3 and Mistral test with the *currently saved* config or the *currently entered* config? The answer is: the currently entered values, because the ViewModel passes them. But this isn't communicated. If you type a new API key and hit Test before Save, does it test the new key?

**Recommendations:**
- **A.** Label the buttons "Test Connection" instead of just "Test" for clarity.
- **B.** If testing unsaved values, add a subtle note: "Tests with current values (unsaved)".
- **C.** Visually connect the test button to its section more clearly — currently it's just at the bottom of the section with no visual grouping.

## 18. Liquid Glass / macOS 26 Considerations

**Finding:** The app uses a standard `NSPopover` with basic SwiftUI views. It doesn't adopt any Liquid Glass materials, vibrancy effects, or the translucent layering that macOS 26 emphasizes.

**Recommendations:**
- **A.** Add `.background(.ultraThinMaterial)` or `.background(.regularMaterial)` to the popover content for the frosted-glass look that's standard in macOS menu bar apps.
- **B.** Use vibrancy-aware foreground styles — `.primary`, `.secondary`, `.tertiary` are good (already used), but ensure they work well on material backgrounds.
- **C.** The drop zone dashed border should use a material-aware stroke color rather than `.clear`/`.accentColor` — consider `.quaternary` for the resting state so it's always subtly visible.
- **D.** Section headers in the job list and settings form should use the system's `.sidebar` or `.insetGrouped` list styles for automatic Liquid Glass adaptation.
- **E.** Consider using `.glassEffect()` modifier (macOS 26) on prominent interactive elements like the drop zone and primary buttons.

## 19. The Entire Popover Is One Flat Surface

**Finding:** There's no depth or layering. Banners, drop zone, job list, and footer all sit on the same flat plane with only `Divider()` lines separating them.

**Recommendations:**
- **A.** Give banners a stronger visual treatment — use `.background(.thickMaterial)` with a colored tint instead of `color.opacity(0.1)`.
- **B.** The drop zone should feel like a recessed well (subtle inner shadow or `.background(.thinMaterial)` with rounded corners) to communicate "drop target."
- **C.** The footer/toolbar should have a distinct background from the content area — even a subtle `.ultraThinMaterial` difference creates useful layering.
- **D.** Per Apple HIG: use visual depth to communicate hierarchy. Elevated elements are interactive, recessed elements receive content.

## 20. No Animations or Transitions

**Finding:** View transitions between main content and settings are instant (`if showSettings`). Job status changes are instant. Banners appear/disappear instantly. The compact-to-hidden drop zone transition is instant.

**Recommendations:**
- **A.** Add `.animation(.easeInOut(duration: 0.2))` to the settings toggle transition — a horizontal slide would feel native.
- **B.** Animate job row status changes — crossfade between progress indicator and "Done" checkmark.
- **C.** Animate banner appearance/dismissal with `.transition(.move(edge: .top).combined(with: .opacity))`.
- **D.** Animate the drop zone mode transitions (full → compact → hidden) rather than instant layout jumps.
- **E.** Add a subtle scale-up animation when a new job row appears.

## 21. The Gear Icon Is Lonely and Unintuitive

**Finding:** The footer is just `HStack { Spacer(); gearButton }` — a small gear icon floating in the bottom-right with 44pt of hit area but only 14pt of visible content. It's the only element in the footer.

**Recommendations:**
- **A.** Move settings access to a header bar (see point 5). The bottom-right corner is the *least* scanned area of a popover.
- **B.** If keeping it in the footer, add more utility there — e.g. a job count ("3 files processed"), the app name, or a "Quit" option.
- **C.** Replace the lone gear with a proper toolbar: `[app name/icon] [spacer] [+add] [gear]`.

## 22. No Quit/Close Option in the Popover

**Finding:** There's no way to quit the app from the popover. Users must go to Activity Monitor or use Cmd+Q (but since it's an accessory app, Cmd+Q may not work as expected). There's no right-click menu on the status bar icon either.

**Recommendations:**
- **A.** Add a "Quit trnscrb" option — either in the footer, in settings, or as a right-click menu on the menu bar icon.
- **B.** Per Apple HIG: menu bar apps should provide a way to quit from the menu/popover.

## 23. Duplicate `LockedURLStore` Class

**Finding:** `LockedURLStore` is defined identically in both `PopoverView.swift` and `DropZoneView.swift` as `private` classes. This is a code smell that also suggests the drop handling logic is duplicated.

**Recommendations:**
- **A.** Extract to a single shared internal utility.
- **B.** Consider whether the popover-level `onDrop` handler is even necessary — if the `DropZoneView` already handles drops, the popover-level handler is redundant except when the drop zone is hidden.

## 24. No Progress Summary in Menu Bar Icon

**Finding:** While files are processing, the menu bar icon remains static (`doc.text`). There's no badge, no progress indication, no count of active jobs. Users have to open the popover to check status.

**Recommendations:**
- **A.** Show an active job count badge on the menu bar icon (like Mail shows unread count).
- **B.** Alternatively, animate the menu bar icon during processing (subtle pulse or spinning indicator) — macOS allows NSStatusBarButton image changes.
- **C.** Consider showing a mini-progress ring around the menu bar icon for single-file processing.

## 25. Settings Form Sections Are Dense

**Finding:** The S3 section has 7 fields plus a test button. That's a lot for a 320pt-wide form. All fields look identical — same rounded border, same font size, no visual grouping between "required" and "optional" fields.

**Recommendations:**
- **A.** Group required fields (endpoint, access key, secret key, bucket) visually separate from optional ones (region, path prefix) using a subsection or visual divider.
- **B.** Mark required fields with a subtle asterisk or "Required" label.
- **C.** Use placeholder text more effectively — show example values (e.g. `"https://s3.amazonaws.com"` for endpoint, `"us-east-1"` for region).
- **D.** Consider a setup wizard for first-time configuration rather than dumping all fields at once.

## 26. File Saving Should Be Required (Not Optional)

**Finding:** Currently `saveToFolder` is a toggle that defaults to `false`, and `copyToClipboard` defaults to `true`. This means by default the app is clipboard-only with no persistent record of transcriptions. The completed job list (max 10, in-memory only) is the only "history" — once the app restarts, all results are gone. Without file saving, there's no way to recover past transcriptions, no way to "Open in Finder", and the completed row actions are limited to clipboard copy.

**Recommendations:**
- **A.** Make file saving always-on (remove the toggle). Every transcription should produce a `.md` file on disk. This gives users a persistent history without needing a database.
- **B.** Keep the clipboard toggle as an *additional* convenience on top of file saving.
- **C.** With file saving guaranteed, the completed job row can always offer "Reveal in Finder" and "Open" actions — no conditional logic needed.
- **D.** The save folder path becomes a required setting (not optional), which simplifies the settings validation logic.
- **E.** Consider showing the saved file path on the completed job row as a clickable breadcrumb.
