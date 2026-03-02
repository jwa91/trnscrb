# Phase 3 — Integration

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire the end-to-end pipeline so that dropping a file produces markdown — `ProcessFileUseCase` orchestrates S3 upload → Mistral API → delivery, `JobListViewModel` tracks progress, and drag-and-drop works both in the popover and on the menu bar icon.

**Architecture:** `ProcessFileUseCase` (domain) orchestrates the pipeline through gateway protocols. `JobListViewModel` (presentation) owns `Job` state, calls the use case, and updates `Job` state via a stage-change callback. `CompositeDelivery` (infrastructure) delegates to `ClipboardDelivery` and/or `FileDelivery` based on settings. `AppDelegate` (composition root) wires everything. A new `StatusBarDropView` (AppKit `NSView`) registers as a drag destination on the status bar button.

**Tech Stack:** Swift 6, SwiftUI (`.onDrop`, `NSOpenPanel`), AppKit (`NSDraggingDestination`, `NSPasteboard`), Swift Testing (`@Test`, `#expect`)

---

## Task 1: Add `saveToFolder` Setting + CompositeDelivery

The SPEC defines two output modes: clipboard (default) and save-to-folder (opt-in). The current `AppSettings` has `copyToClipboard: Bool` for clipboard but no toggle for file save. Add `saveToFolder: Bool = false` and create a `CompositeDelivery` that checks both settings at delivery time.

**Files:**
- Modify: `trnscrb/Domain/Entities/AppSettings.swift`
- Modify: `trnscrb/Infrastructure/Config/TOMLConfigManager.swift`
- Modify: `trnscrb/Presentation/Settings/SettingsView.swift`
- Create: `trnscrb/Infrastructure/Delivery/CompositeDelivery.swift`
- Create: `Tests/Infrastructure/CompositeDeliveryTests.swift`
- Modify: `Tests/Infrastructure/TOMLConfigManagerTests.swift`

### Step 1: Add `saveToFolder` to AppSettings

In `trnscrb/Domain/Entities/AppSettings.swift`, add the field:

```swift
// Add after copyToClipboard property (line 29):
/// Whether to save markdown output to a file in the save folder.
public var saveToFolder: Bool

// Update init to include it (add after copyToClipboard parameter):
saveToFolder: Bool = false,

// Add assignment in init body (after self.copyToClipboard = copyToClipboard):
self.saveToFolder = saveToFolder
```

### Step 2: Update TOMLConfigManager serialization

In `trnscrb/Infrastructure/Config/TOMLConfigManager.swift`:

```swift
// In serialize() — add after the copy_to_clipboard line (line 94):
"save_to_folder = \(settings.saveToFolder)",

// In parse() — add after copyToClipboard in the AppSettings constructor (after line 122):
saveToFolder: dict["save_to_folder"].map { $0 == "true" } ?? defaults.saveToFolder,
```

### Step 3: Update SettingsView toggle

In `trnscrb/Presentation/Settings/SettingsView.swift`, in the `outputSection` (line 89–95):

```swift
private var outputSection: some View {
    Section("Output") {
        TextField("Save Folder", text: $viewModel.settings.saveFolderPath)
            .textFieldStyle(.roundedBorder)
        Toggle("Save markdown to folder", isOn: $viewModel.settings.saveToFolder)
        Toggle("Copy markdown to clipboard", isOn: $viewModel.settings.copyToClipboard)
    }
}
```

### Step 4: Update TOML round-trip test

In `Tests/Infrastructure/TOMLConfigManagerTests.swift`, update `roundTripPreservesAllFields` (line 45–58) to include the new field:

```swift
let original: AppSettings = AppSettings(
    s3EndpointURL: "https://nbg1.your-objectstorage.com",
    s3AccessKey: "AKID123",
    s3BucketName: "my-bucket",
    s3Region: "eu-central-1",
    s3PathPrefix: "uploads/",
    saveFolderPath: "~/Desktop/output/",
    copyToClipboard: false,
    saveToFolder: true,
    fileRetentionHours: 48,
    launchAtLogin: true
)
```

### Step 5: Write CompositeDelivery tests

Create `Tests/Infrastructure/CompositeDeliveryTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

/// Records calls without side effects.
private final class SpyDelivery: DeliveryGateway, @unchecked Sendable {
    var delivered: [TranscriptionResult] = []

    func deliver(result: TranscriptionResult) async throws {
        delivered.append(result)
    }
}

private func makeResult() -> TranscriptionResult {
    TranscriptionResult(markdown: "# Hello", sourceFileName: "test.mp3", sourceFileType: .audio)
}

struct CompositeDeliveryTests {
    @Test func deliversToClipboardWhenEnabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings.copyToClipboard = true
        gateway.settings.saveToFolder = false
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        try await delivery.deliver(result: makeResult())
        #expect(clipboard.delivered.count == 1)
        #expect(file.delivered.count == 0)
    }

    @Test func deliversToFileWhenEnabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings.copyToClipboard = false
        gateway.settings.saveToFolder = true
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        try await delivery.deliver(result: makeResult())
        #expect(clipboard.delivered.count == 0)
        #expect(file.delivered.count == 1)
    }

    @Test func deliversToBothWhenBothEnabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings.copyToClipboard = true
        gateway.settings.saveToFolder = true
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        try await delivery.deliver(result: makeResult())
        #expect(clipboard.delivered.count == 1)
        #expect(file.delivered.count == 1)
    }

    @Test func deliversToNeitherWhenBothDisabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings.copyToClipboard = false
        gateway.settings.saveToFolder = false
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        try await delivery.deliver(result: makeResult())
        #expect(clipboard.delivered.count == 0)
        #expect(file.delivered.count == 0)
    }
}
```

### Step 6: Run tests to verify they fail

Run: `swift test --filter CompositeDeliveryTests 2>&1 | tail -5`
Expected: compile error — `CompositeDelivery` not defined.

### Step 7: Implement CompositeDelivery

Create `trnscrb/Infrastructure/Delivery/CompositeDelivery.swift`:

```swift
import Foundation

/// Routes delivery to clipboard and/or file based on current settings.
///
/// Each delivery target is an independent `DeliveryGateway`. Settings are checked
/// at delivery time so toggling a mode takes effect immediately.
public struct CompositeDelivery: DeliveryGateway {
    /// Clipboard delivery handler.
    private let clipboard: any DeliveryGateway
    /// File-save delivery handler.
    private let file: any DeliveryGateway
    /// Reads settings to determine which modes are active.
    private let settingsGateway: any SettingsGateway

    /// Creates a composite delivery.
    /// - Parameters:
    ///   - clipboard: Delivery handler for clipboard output.
    ///   - file: Delivery handler for file-save output.
    ///   - settingsGateway: Provides current output mode settings.
    public init(
        clipboard: any DeliveryGateway,
        file: any DeliveryGateway,
        settingsGateway: any SettingsGateway
    ) {
        self.clipboard = clipboard
        self.file = file
        self.settingsGateway = settingsGateway
    }

    /// Delivers the result to all enabled output modes.
    public func deliver(result: TranscriptionResult) async throws {
        let settings: AppSettings = try await settingsGateway.loadSettings()
        if settings.copyToClipboard {
            try await clipboard.deliver(result: result)
        }
        if settings.saveToFolder {
            try await file.deliver(result: result)
        }
    }
}
```

### Step 8: Run all tests

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass.

### Step 9: Commit

```bash
git add trnscrb/Domain/Entities/AppSettings.swift \
  trnscrb/Infrastructure/Config/TOMLConfigManager.swift \
  trnscrb/Presentation/Settings/SettingsView.swift \
  trnscrb/Infrastructure/Delivery/CompositeDelivery.swift \
  Tests/Infrastructure/CompositeDeliveryTests.swift \
  Tests/Infrastructure/TOMLConfigManagerTests.swift
git commit -m "feat: add saveToFolder setting and CompositeDelivery"
```

---

## Task 2: ProcessFileUseCase (TDD)

Implement the core pipeline orchestrator. It validates the file type, uploads to S3, finds the matching transcriber, calls the API, and delivers the result. Reports stage changes via an optional callback so the ViewModel can update Job state.

**Files:**
- Create: `Tests/Helpers/MockStorageGateway.swift`
- Create: `Tests/Helpers/MockTranscriptionGateway.swift`
- Create: `Tests/Helpers/MockDeliveryGateway.swift`
- Create: `Tests/Domain/ProcessFileUseCaseTests.swift`
- Modify: `trnscrb/Domain/UseCases/ProcessFileUseCase.swift`

### Step 1: Create mock gateways

Create `Tests/Helpers/MockStorageGateway.swift`:

```swift
import Foundation

@testable import trnscrb

final class MockStorageGateway: StorageGateway, @unchecked Sendable {
    /// URL returned by upload. Set before calling.
    var uploadResult: URL = URL(string: "https://s3.example.com/bucket/file.mp3")!
    /// If set, upload throws this error.
    var uploadError: (any Error)?
    /// Records uploaded keys.
    var uploadedKeys: [String] = []

    func upload(fileURL: URL, key: String) async throws -> URL {
        if let error = uploadError { throw error }
        uploadedKeys.append(key)
        return uploadResult
    }

    func delete(key: String) async throws {}
    func listCreatedBefore(_ cutoff: Date) async throws -> [String] { [] }
}
```

Create `Tests/Helpers/MockTranscriptionGateway.swift`:

```swift
import Foundation

@testable import trnscrb

final class MockTranscriptionGateway: TranscriptionGateway, @unchecked Sendable {
    let supportedExtensions: Set<String>
    /// Markdown returned by process. Set before calling.
    var processResult: String = "# Transcribed"
    /// If set, process throws this error.
    var processError: (any Error)?
    /// Records URLs passed to process.
    var processedURLs: [URL] = []

    init(supportedExtensions: Set<String>) {
        self.supportedExtensions = supportedExtensions
    }

    func process(sourceURL: URL) async throws -> String {
        if let error = processError { throw error }
        processedURLs.append(sourceURL)
        return processResult
    }
}
```

Create `Tests/Helpers/MockDeliveryGateway.swift`:

```swift
import Foundation

@testable import trnscrb

final class MockDeliveryGateway: DeliveryGateway, @unchecked Sendable {
    /// Records delivered results.
    var deliveredResults: [TranscriptionResult] = []
    /// If set, deliver throws this error.
    var deliverError: (any Error)?

    func deliver(result: TranscriptionResult) async throws {
        if let error = deliverError { throw error }
        deliveredResults.append(result)
    }
}
```

### Step 2: Write ProcessFileUseCase tests

Create `Tests/Domain/ProcessFileUseCaseTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

private func makeUseCase(
    storage: MockStorageGateway = MockStorageGateway(),
    audioTranscriber: MockTranscriptionGateway = MockTranscriptionGateway(
        supportedExtensions: FileType.audioExtensions
    ),
    ocrTranscriber: MockTranscriptionGateway = MockTranscriptionGateway(
        supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions)
    ),
    delivery: MockDeliveryGateway = MockDeliveryGateway(),
    settings: MockSettingsGateway = MockSettingsGateway()
) -> (ProcessFileUseCase, MockStorageGateway, MockTranscriptionGateway, MockTranscriptionGateway, MockDeliveryGateway, MockSettingsGateway) {
    settings.settings.s3PathPrefix = "trnscrb/"
    let useCase: ProcessFileUseCase = ProcessFileUseCase(
        storage: storage,
        transcribers: [audioTranscriber, ocrTranscriber],
        delivery: delivery,
        settings: settings
    )
    return (useCase, storage, audioTranscriber, ocrTranscriber, delivery, settings)
}

struct ProcessFileUseCaseTests {
    // MARK: - Happy path

    @Test func processAudioFile() async throws {
        let (useCase, storage, audioTranscriber, _, delivery, _) = makeUseCase()
        let presignedURL: URL = URL(string: "https://s3.example.com/presigned")!
        storage.uploadResult = presignedURL
        audioTranscriber.processResult = "# Meeting Notes"

        let fileURL: URL = URL(filePath: "/tmp/meeting.mp3")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.markdown == "# Meeting Notes")
        #expect(result.sourceFileName == "meeting.mp3")
        #expect(result.sourceFileType == .audio)
        #expect(storage.uploadedKeys.count == 1)
        #expect(storage.uploadedKeys[0].hasPrefix("trnscrb/"))
        #expect(storage.uploadedKeys[0].hasSuffix(".mp3"))
        #expect(audioTranscriber.processedURLs == [presignedURL])
        #expect(delivery.deliveredResults.count == 1)
    }

    @Test func processPDFFile() async throws {
        let (useCase, _, _, ocrTranscriber, _, _) = makeUseCase()
        ocrTranscriber.processResult = "# Document"

        let fileURL: URL = URL(filePath: "/tmp/scan.pdf")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.markdown == "# Document")
        #expect(result.sourceFileType == .pdf)
        #expect(ocrTranscriber.processedURLs.count == 1)
    }

    @Test func processImageFile() async throws {
        let (useCase, _, _, ocrTranscriber, _, _) = makeUseCase()
        ocrTranscriber.processResult = "# Handwritten Note"

        let fileURL: URL = URL(filePath: "/tmp/notes.png")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.markdown == "# Handwritten Note")
        #expect(result.sourceFileType == .image)
        #expect(ocrTranscriber.processedURLs.count == 1)
    }

    // MARK: - S3 key format

    @Test func s3KeyUsesPathPrefixAndUUIDAndExtension() async throws {
        let storage: MockStorageGateway = MockStorageGateway()
        let settings: MockSettingsGateway = MockSettingsGateway()
        settings.settings.s3PathPrefix = "custom/"
        let (useCase, _, _, _, _, _) = makeUseCase(storage: storage, settings: settings)

        _ = try await useCase.execute(fileURL: URL(filePath: "/tmp/test.wav"))

        let key: String = storage.uploadedKeys[0]
        #expect(key.hasPrefix("custom/"))
        #expect(key.hasSuffix(".wav"))
        // UUID is 36 chars: 8-4-4-4-12. Key = "custom/" + UUID + ".wav" = 7 + 36 + 4 = 47
        #expect(key.count == 47)
    }

    // MARK: - Stage changes

    @Test func reportsStageChangesInOrder() async throws {
        let (useCase, _, _, _, _, _) = makeUseCase()
        var stages: [ProcessingStage] = []

        _ = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/test.mp3")
        ) { stage in
            stages.append(stage)
        }

        #expect(stages == [.uploading, .processing])
    }

    // MARK: - Error cases

    @Test func throwsForUnsupportedFileType() async throws {
        let (useCase, _, _, _, _, _) = makeUseCase()

        await #expect(throws: ProcessFileError.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/file.xyz"))
        }
    }

    @Test func propagatesS3UploadError() async throws {
        let storage: MockStorageGateway = MockStorageGateway()
        storage.uploadError = S3Error.requestFailed(statusCode: 500, body: "Internal")
        let (useCase, _, _, _, _, _) = makeUseCase(storage: storage)

        await #expect(throws: S3Error.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))
        }
    }

    @Test func propagatesTranscriptionError() async throws {
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        audio.processError = MistralError.requestFailed(statusCode: 500, body: "Error")
        let (useCase, _, _, _, _, _) = makeUseCase(audioTranscriber: audio)

        await #expect(throws: MistralError.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))
        }
    }

    @Test func doesNotDeliverOnTranscriptionFailure() async throws {
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        audio.processError = MistralError.requestFailed(statusCode: 500, body: "Error")
        let delivery: MockDeliveryGateway = MockDeliveryGateway()
        let (useCase, _, _, _, _, _) = makeUseCase(audioTranscriber: audio, delivery: delivery)

        _ = try? await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))

        #expect(delivery.deliveredResults.isEmpty)
    }

    // MARK: - Extension case insensitivity

    @Test func handlesUppercaseExtension() async throws {
        let (useCase, _, _, _, _, _) = makeUseCase()

        let result: TranscriptionResult = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/photo.JPEG")
        )

        #expect(result.sourceFileType == .image)
    }
}
```

### Step 3: Run tests to verify they fail

Run: `swift test --filter ProcessFileUseCaseTests 2>&1 | tail -5`
Expected: compile errors — `ProcessingStage` and `ProcessFileError` not defined, `execute` has wrong signature.

### Step 4: Implement ProcessFileUseCase

Replace `trnscrb/Domain/UseCases/ProcessFileUseCase.swift` entirely:

```swift
import Foundation

/// Errors from the file processing pipeline.
public enum ProcessFileError: Error, Sendable, Equatable {
    /// The file extension is not supported by any provider.
    case unsupportedFileType(String)
}

/// Stages of the processing pipeline, reported via callback.
public enum ProcessingStage: Sendable, Equatable {
    /// File is being uploaded to object storage.
    case uploading
    /// File uploaded, transcription/OCR in progress.
    case processing
}

/// Orchestrates the full file processing pipeline: upload -> transcribe -> deliver.
///
/// This is the core use case. It:
/// 1. Validates the file extension and determines the file type
/// 2. Uploads the dropped file to S3 via `StorageGateway`
/// 3. Finds the right `TranscriptionGateway` for the file type
/// 4. Calls the transcription/OCR API with the presigned URL
/// 5. Delivers the markdown result via `DeliveryGateway`
public final class ProcessFileUseCase: Sendable {
    /// Object storage for uploading files.
    private let storage: any StorageGateway
    /// Available transcription/OCR providers (matched by file extension).
    private let transcribers: [any TranscriptionGateway]
    /// Delivers results to the user (clipboard, file, or both).
    private let delivery: any DeliveryGateway
    /// Settings for S3 path prefix and other config.
    private let settings: any SettingsGateway

    /// Creates the use case with injected dependencies.
    public init(
        storage: any StorageGateway,
        transcribers: [any TranscriptionGateway],
        delivery: any DeliveryGateway,
        settings: any SettingsGateway
    ) {
        self.storage = storage
        self.transcribers = transcribers
        self.delivery = delivery
        self.settings = settings
    }

    /// Processes a dropped file end-to-end.
    /// - Parameters:
    ///   - fileURL: Local path to the file.
    ///   - onStageChange: Optional callback reporting pipeline stage transitions.
    /// - Returns: The transcription result with markdown content.
    public func execute(
        fileURL: URL,
        onStageChange: (@Sendable (ProcessingStage) -> Void)? = nil
    ) async throws -> TranscriptionResult {
        let ext: String = fileURL.pathExtension.lowercased()

        guard let fileType: FileType = FileType.from(extension: ext) else {
            throw ProcessFileError.unsupportedFileType(ext)
        }

        guard let transcriber = transcribers.first(
            where: { $0.supportedExtensions.contains(ext) }
        ) else {
            throw ProcessFileError.unsupportedFileType(ext)
        }

        let appSettings: AppSettings = try await settings.loadSettings()
        let key: String = "\(appSettings.s3PathPrefix)\(UUID().uuidString).\(ext)"

        onStageChange?(.uploading)
        let presignedURL: URL = try await storage.upload(fileURL: fileURL, key: key)

        onStageChange?(.processing)
        let markdown: String = try await transcriber.process(sourceURL: presignedURL)

        let result: TranscriptionResult = TranscriptionResult(
            markdown: markdown,
            sourceFileName: fileURL.lastPathComponent,
            sourceFileType: fileType
        )

        try await delivery.deliver(result: result)

        return result
    }
}
```

### Step 5: Run all tests

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass.

### Step 6: Commit

```bash
git add Tests/Helpers/MockStorageGateway.swift \
  Tests/Helpers/MockTranscriptionGateway.swift \
  Tests/Helpers/MockDeliveryGateway.swift \
  Tests/Domain/ProcessFileUseCaseTests.swift \
  trnscrb/Domain/UseCases/ProcessFileUseCase.swift
git commit -m "feat: implement ProcessFileUseCase with stage reporting"
```

---

## Task 3: JobListViewModel (TDD)

The view model that manages the job queue. Accepts file URLs, creates `Job` instances, drives `ProcessFileUseCase`, updates job state via the stage callback, and tracks recent completed jobs. Also provides copy-to-clipboard for completed jobs.

**Files:**
- Create: `Tests/Presentation/JobListViewModelTests.swift`
- Create: `trnscrb/Presentation/ViewModels/JobListViewModel.swift`

### Step 1: Write JobListViewModel tests

Create `Tests/Presentation/JobListViewModelTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

@MainActor
struct JobListViewModelTests {
    private func makeViewModel(
        storage: MockStorageGateway = MockStorageGateway(),
        delivery: MockDeliveryGateway = MockDeliveryGateway(),
        settings: MockSettingsGateway = {
            let g: MockSettingsGateway = MockSettingsGateway()
            g.settings.s3EndpointURL = "https://s3.example.com"
            g.settings.s3AccessKey = "AKID"
            g.settings.s3BucketName = "bucket"
            g.secrets[.mistralAPIKey] = "mk-test"
            g.secrets[.s3SecretKey] = "sk-test"
            return g
        }()
    ) -> (JobListViewModel, MockStorageGateway, MockDeliveryGateway, MockSettingsGateway) {
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        let ocr: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions)
        )
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: storage,
            transcribers: [audio, ocr],
            delivery: delivery,
            settings: settings
        )
        let vm: JobListViewModel = JobListViewModel(
            useCase: useCase,
            settingsGateway: settings
        )
        return (vm, storage, delivery, settings)
    }

    // MARK: - File validation

    @Test func rejectsUnsupportedFileType() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([URL(filePath: "/tmp/file.xyz")])
        #expect(vm.jobs.isEmpty)
    }

    @Test func createsJobForSupportedFile() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        #expect(vm.jobs.count == 1)
        #expect(vm.jobs[0].fileType == .audio)
        #expect(vm.jobs[0].fileName == "test.mp3")
    }

    @Test func createsJobsForMultipleFiles() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([
            URL(filePath: "/tmp/audio.mp3"),
            URL(filePath: "/tmp/doc.pdf"),
            URL(filePath: "/tmp/photo.png")
        ])
        #expect(vm.jobs.count == 3)
    }

    @Test func filtersUnsupportedFromMixedBatch() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([
            URL(filePath: "/tmp/good.mp3"),
            URL(filePath: "/tmp/bad.xyz"),
            URL(filePath: "/tmp/good.pdf")
        ])
        #expect(vm.jobs.count == 2)
    }

    // MARK: - Configuration checks

    @Test func setsConfigErrorWhenS3NotConfigured() async {
        let settings: MockSettingsGateway = MockSettingsGateway()
        // s3EndpointURL is empty by default — not configured
        settings.secrets[.mistralAPIKey] = "mk-test"
        let (vm, _, _, _) = makeViewModel(settings: settings)

        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        // Allow async configuration check to complete
        try? await Task.sleep(for: .milliseconds(50))

        #expect(vm.configurationError != nil)
        #expect(vm.jobs.isEmpty)
    }

    @Test func setsConfigErrorWhenAPIKeyMissing() async {
        let settings: MockSettingsGateway = MockSettingsGateway()
        settings.settings.s3EndpointURL = "https://s3.example.com"
        settings.settings.s3AccessKey = "AKID"
        settings.settings.s3BucketName = "bucket"
        // No Mistral API key
        settings.secrets[.s3SecretKey] = "sk-test"
        let (vm, _, _, _) = makeViewModel(settings: settings)

        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        try? await Task.sleep(for: .milliseconds(50))

        #expect(vm.configurationError != nil)
        #expect(vm.jobs.isEmpty)
    }

    // MARK: - Completed jobs history

    @Test func completedJobsListHasMaxTenItems() async {
        let (vm, _, _, _) = makeViewModel()

        // Process 12 files
        for i in 0..<12 {
            vm.processFiles([URL(filePath: "/tmp/file\(i).mp3")])
        }
        // Allow processing to complete
        try? await Task.sleep(for: .milliseconds(200))

        let completed: [Job] = vm.completedJobs
        #expect(completed.count <= 10)
    }

    // MARK: - Computed properties

    @Test func activeJobsFiltersCorrectly() async {
        let (vm, _, _, _) = makeViewModel()
        vm.processFiles([URL(filePath: "/tmp/test.mp3")])
        // Job should be active immediately after creation
        #expect(vm.activeJobs.count == 1)
    }
}
```

### Step 2: Run tests to verify they fail

Run: `swift test --filter JobListViewModelTests 2>&1 | tail -5`
Expected: compile error — `JobListViewModel` not defined.

### Step 3: Implement JobListViewModel

Create `trnscrb/Presentation/ViewModels/JobListViewModel.swift`:

```swift
import AppKit
import Foundation

/// Manages the job queue and coordinates file processing.
///
/// Accepts file URLs from drag-and-drop, validates file types, creates `Job`
/// instances, and drives `ProcessFileUseCase` while updating job state. Tracks
/// recent completed jobs (max 10) and provides copy-to-clipboard for results.
@MainActor
public final class JobListViewModel: ObservableObject {
    /// All jobs, both active and completed.
    @Published public var jobs: [Job] = []
    /// Error message when S3 or API key is not configured.
    @Published public var configurationError: String?

    /// Maximum number of completed jobs to retain.
    private let maxCompletedJobs: Int = 10
    /// Pipeline orchestrator.
    private let useCase: ProcessFileUseCase
    /// Settings gateway for configuration checks.
    private let settingsGateway: any SettingsGateway

    /// Creates a job list view model.
    /// - Parameters:
    ///   - useCase: Pipeline orchestrator for processing files.
    ///   - settingsGateway: Settings gateway for pre-flight configuration checks.
    public init(useCase: ProcessFileUseCase, settingsGateway: any SettingsGateway) {
        self.useCase = useCase
        self.settingsGateway = settingsGateway
    }

    /// Jobs that are still active (pending, uploading, or processing).
    public var activeJobs: [Job] {
        jobs.filter { job in
            switch job.status {
            case .pending, .uploading, .processing:
                return true
            case .completed, .failed:
                return false
            }
        }
    }

    /// Jobs that have completed or failed, newest first.
    public var completedJobs: [Job] {
        jobs.filter { job in
            switch job.status {
            case .completed, .failed:
                return true
            case .pending, .uploading, .processing:
                return false
            }
        }
    }

    /// Validates and queues files for processing.
    ///
    /// Unsupported file types are silently filtered. If S3 or API key is not
    /// configured, sets `configurationError` and does not process.
    /// - Parameter urls: Local file URLs from drag-and-drop or file picker.
    public func processFiles(_ urls: [URL]) {
        let validURLs: [(URL, FileType)] = urls.compactMap { url in
            let ext: String = url.pathExtension.lowercased()
            guard let fileType: FileType = FileType.from(extension: ext) else { return nil }
            return (url, fileType)
        }
        guard !validURLs.isEmpty else { return }

        Task {
            guard await checkConfiguration() else { return }
            configurationError = nil

            for (url, fileType) in validURLs {
                let job: Job = Job(fileType: fileType, fileURL: url)
                jobs.append(job)
                let jobID: UUID = job.id

                Task {
                    await processJob(id: jobID)
                }
            }
        }
    }

    /// Copies the markdown from a completed job to the clipboard.
    /// - Parameter jobID: ID of the completed job.
    public func copyToClipboard(jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }),
              let markdown: String = job.markdown else { return }
        let pasteboard: NSPasteboard = .general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
    }

    // MARK: - Private

    /// Checks that S3 and Mistral API key are configured.
    /// - Returns: `true` if configuration is valid, `false` otherwise.
    private func checkConfiguration() async -> Bool {
        do {
            let settings: AppSettings = try await settingsGateway.loadSettings()
            guard settings.isS3Configured else {
                configurationError = "Configure your S3 storage in settings."
                return false
            }
            guard let apiKey: String = try await settingsGateway.getSecret(for: .mistralAPIKey),
                  !apiKey.isEmpty else {
                configurationError = "Configure your Mistral API key in settings."
                return false
            }
            return true
        } catch {
            configurationError = error.localizedDescription
            return false
        }
    }

    /// Processes a single job through the pipeline.
    /// - Parameter id: ID of the job to process.
    private func processJob(id: UUID) async {
        updateJob(id: id) { $0.startUpload() }

        do {
            guard let fileURL: URL = jobs.first(where: { $0.id == id })?.fileURL else { return }

            let result: TranscriptionResult = try await useCase.execute(
                fileURL: fileURL
            ) { [weak self] stage in
                guard let self else { return }
                Task { @MainActor in
                    switch stage {
                    case .uploading:
                        break // Already set above
                    case .processing:
                        self.updateJob(id: id) { $0.startProcessing() }
                    }
                }
            }

            updateJob(id: id) { $0.complete(markdown: result.markdown) }
        } catch {
            updateJob(id: id) { $0.fail(error: error.localizedDescription) }
        }

        trimCompletedJobs()
    }

    /// Applies a mutation to the job with the given ID.
    private func updateJob(id: UUID, _ mutation: (inout Job) -> Void) {
        guard let index: Int = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutation(&jobs[index])
    }

    /// Removes the oldest completed/failed jobs beyond the retention limit.
    private func trimCompletedJobs() {
        let completed: [Job] = completedJobs
        guard completed.count > maxCompletedJobs else { return }
        let toRemove: Int = completed.count - maxCompletedJobs
        let idsToRemove: Set<UUID> = Set(
            completed.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
                .prefix(toRemove)
                .map(\.id)
        )
        jobs.removeAll { idsToRemove.contains($0.id) }
    }
}
```

### Step 4: Run all tests

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass.

### Step 5: Commit

```bash
git add Tests/Presentation/JobListViewModelTests.swift \
  trnscrb/Presentation/ViewModels/JobListViewModel.swift
git commit -m "feat: implement JobListViewModel with job queue and config checks"
```

---

## Task 4: DropZoneView + JobListView

Build the SwiftUI views for the popover. `DropZoneView` accepts file drops and has a click-to-select fallback. `JobRowView` renders a single job's status. `JobListView` shows active and completed jobs.

**Files:**
- Create: `trnscrb/Presentation/Popover/DropZoneView.swift`
- Create: `trnscrb/Presentation/Popover/JobRowView.swift`
- Create: `trnscrb/Presentation/Popover/JobListView.swift`

### Step 1: Create DropZoneView

Create `trnscrb/Presentation/Popover/DropZoneView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

/// A drop zone that accepts files via drag-and-drop or a file picker fallback.
///
/// Shows a visual target area with hover feedback. Validates file types
/// using `FileType.allSupported` and calls `onDrop` with valid URLs.
struct DropZoneView: View {
    /// Called with the URLs of dropped/selected files.
    var onDrop: ([URL]) -> Void
    /// Tracks whether a drag is hovering over the zone.
    @State private var isTargeted: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundStyle(isTargeted ? .accent : .secondary)
            Text("Drop files here")
                .font(.headline)
            Text("or drag onto the menu bar icon")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Choose Files\u{2026}") {
                openFilePicker()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .padding(8)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// Extracts file URLs from drop providers and calls onDrop.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group: DispatchGroup = DispatchGroup()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url: URL = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let supported: [URL] = urls.filter {
                FileType.allSupported.contains($0.pathExtension.lowercased())
            }
            if !supported.isEmpty {
                onDrop(supported)
            }
        }
        return true
    }

    /// Opens a macOS file picker dialog for selecting files.
    private func openFilePicker() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let extensions: [UTType] = FileType.allSupported.compactMap { ext in
            UTType(filenameExtension: ext)
        }
        panel.allowedContentTypes = extensions
        panel.begin { response in
            if response == .OK {
                onDrop(panel.urls)
            }
        }
    }
}
```

### Step 2: Create JobRowView

Create `trnscrb/Presentation/Popover/JobRowView.swift`:

```swift
import SwiftUI

/// A single row in the job list showing file name, type icon, and status.
struct JobRowView: View {
    /// The job to display.
    let job: Job
    /// Called when the user clicks a completed job to copy its markdown.
    var onCopy: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: fileTypeIcon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(job.fileName)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.caption)
            Spacer()
            statusView
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if case .completed = job.status {
                onCopy?()
            }
        }
    }

    /// SF Symbol name for the file type.
    private var fileTypeIcon: String {
        switch job.fileType {
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        }
    }

    /// Status indicator view.
    @ViewBuilder
    private var statusView: some View {
        switch job.status {
        case .pending:
            Text("Waiting")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .uploading(let progress):
            ProgressView(value: progress)
                .frame(width: 40)
        case .processing:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamation.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}
```

### Step 3: Create JobListView

Create `trnscrb/Presentation/Popover/JobListView.swift`:

```swift
import SwiftUI

/// Displays active and recently completed jobs in the popover.
struct JobListView: View {
    /// The job list view model.
    @ObservedObject var viewModel: JobListViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !viewModel.activeJobs.isEmpty {
                    Section {
                        ForEach(viewModel.activeJobs) { job in
                            JobRowView(job: job)
                            Divider()
                        }
                    } header: {
                        sectionHeader("Active")
                    }
                }

                if !viewModel.completedJobs.isEmpty {
                    Section {
                        ForEach(viewModel.completedJobs) { job in
                            JobRowView(job: job) {
                                viewModel.copyToClipboard(jobID: job.id)
                            }
                            Divider()
                        }
                    } header: {
                        sectionHeader("Recent")
                    }
                }
            }
        }
    }

    /// Section header label.
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
```

### Step 4: Commit

```bash
git add trnscrb/Presentation/Popover/DropZoneView.swift \
  trnscrb/Presentation/Popover/JobRowView.swift \
  trnscrb/Presentation/Popover/JobListView.swift
git commit -m "feat: add DropZoneView, JobRowView, and JobListView"
```

---

## Task 5: PopoverView Integration + AppDelegate Wiring

Update `PopoverView` to use the new views. Update `AppDelegate` to create all infrastructure, wire `ProcessFileUseCase`, and inject `JobListViewModel` into the view hierarchy.

**Files:**
- Modify: `trnscrb/Presentation/Popover/PopoverView.swift`
- Modify: `trnscrb/App/AppDelegate.swift`

### Step 1: Update PopoverView

Replace `trnscrb/Presentation/Popover/PopoverView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

/// Root view displayed inside the menu bar popover.
///
/// Shows the drop zone when idle, job list when processing, and settings
/// panel when toggled. The entire view is always a valid drop target.
struct PopoverView: View {
    /// Controls whether the settings panel is visible.
    @State private var showSettings: Bool = false
    /// View model for the settings panel.
    @ObservedObject var settingsViewModel: SettingsViewModel
    /// View model for the job queue and processing.
    @ObservedObject var jobListViewModel: JobListViewModel

    var body: some View {
        if showSettings {
            SettingsView(
                viewModel: settingsViewModel,
                onBack: { showSettings = false }
            )
        } else {
            mainContent
        }
    }

    /// Main content shown when settings is not active.
    private var mainContent: some View {
        VStack(spacing: 0) {
            if let error: String = jobListViewModel.configurationError {
                configurationBanner(error)
            }

            if jobListViewModel.activeJobs.isEmpty && jobListViewModel.completedJobs.isEmpty {
                DropZoneView(onDrop: jobListViewModel.processFiles)
            } else {
                if jobListViewModel.activeJobs.isEmpty {
                    DropZoneView(onDrop: jobListViewModel.processFiles)
                        .frame(height: 100)
                }
                JobListView(viewModel: jobListViewModel)
            }

            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 320, height: 360)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    /// Banner shown when S3 or API key is not configured.
    private func configurationBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Settings") {
                showSettings = true
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(8)
        .background(.orange.opacity(0.1))
    }

    /// Footer with gear icon.
    private var footer: some View {
        HStack {
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 14))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }

    /// Handles drops on the entire popover surface.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group: DispatchGroup = DispatchGroup()

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url: URL = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let supported: [URL] = urls.filter {
                FileType.allSupported.contains($0.pathExtension.lowercased())
            }
            if !supported.isEmpty {
                jobListViewModel.processFiles(supported)
            }
        }
        return true
    }
}
```

### Step 2: Update AppDelegate

Replace `trnscrb/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

/// Application delegate and composition root.
///
/// Creates the `NSStatusItem` (menu bar icon), manages the `NSPopover`,
/// and wires all infrastructure dependencies. This is the only component
/// that knows about all layers — it creates concrete instances and injects
/// them into view models and use cases.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The menu bar status item showing the app icon.
    private var statusItem: NSStatusItem?
    /// The popover displayed when the status item is clicked.
    private var popover: NSPopover?
    /// Settings gateway for the lifetime of the app.
    private var settingsGateway: (any SettingsGateway)?
    /// Job list view model — retained for status bar drop forwarding.
    private var jobListViewModel: JobListViewModel?
    /// Monitors clicks outside the popover to dismiss it.
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Build infrastructure
        let keychainStore: KeychainStore = KeychainStore()
        let gateway: TOMLConfigManager = TOMLConfigManager(keychainStore: keychainStore)
        settingsGateway = gateway

        let s3Client: S3Client = S3Client(settingsGateway: gateway)
        let audioProvider: MistralAudioProvider = MistralAudioProvider(settingsGateway: gateway)
        let ocrProvider: MistralOCRProvider = MistralOCRProvider(settingsGateway: gateway)
        let clipboardDelivery: ClipboardDelivery = ClipboardDelivery()
        let fileDelivery: FileDelivery = FileDelivery(settingsGateway: gateway)
        let compositeDelivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboardDelivery,
            file: fileDelivery,
            settingsGateway: gateway
        )

        // Build use case
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: s3Client,
            transcribers: [audioProvider, ocrProvider],
            delivery: compositeDelivery,
            settings: gateway
        )

        // Build presentation
        let settingsVM: SettingsViewModel = SettingsViewModel(gateway: gateway)
        let jobListVM: JobListViewModel = JobListViewModel(
            useCase: useCase,
            settingsGateway: gateway
        )
        self.jobListViewModel = jobListVM

        // Setup popover
        let popover: NSPopover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                settingsViewModel: settingsVM,
                jobListViewModel: jobListVM
            )
        )
        self.popover = popover

        // Setup status item
        let statusItem: NSStatusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let button: NSStatusBarButton = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.text",
                accessibilityDescription: "trnscrb"
            )
            button.action = #selector(togglePopover)
            button.target = self
            // Avoid known right-click highlight sticking bug (Jesse Squires).
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])

            // Add drop target overlay
            let dropView: StatusBarDropView = StatusBarDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onDrop = { [weak jobListVM] urls in
                jobListVM?.processFiles(urls)
            }
            button.addSubview(dropView)
        }
        self.statusItem = statusItem
    }

    /// Toggles the popover visibility when the menu bar icon is clicked.
    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Must be async — NSStatusBarButton resets highlight on mouse-up.
            // Dispatching to the next run loop iteration runs after that reset.
            DispatchQueue.main.async {
                button.isHighlighted = true
            }
            startEventMonitor()
        }
    }

    /// Closes the popover and removes the event monitor.
    private func closePopover() {
        popover?.performClose(nil)
    }

    /// Installs a global event monitor that closes the popover on outside clicks.
    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    /// Removes the global event monitor.
    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    /// Called when the popover closes for any reason (click outside, programmatic, etc.).
    /// Unhighlights the status bar button and cleans up the event monitor.
    nonisolated func popoverDidClose(_ notification: Notification) {
        DispatchQueue.main.async { @MainActor in
            self.statusItem?.button?.isHighlighted = false
            self.stopEventMonitor()
        }
    }
}
```

### Step 3: Build and verify compilation

Run: `swift build 2>&1 | tail -5`
Expected: compile error — `StatusBarDropView` not defined. That's created in Task 6.

### Step 4: Commit (combined with Task 6)

This task's commit is deferred to the end of Task 6, since AppDelegate references `StatusBarDropView`.

---

## Task 6: StatusBarDropView (Menu Bar Icon Drag-and-Drop)

Create an `NSView` subclass that sits on top of the status bar button and accepts file drops. This enables the core UX of dragging a file directly onto the menu bar icon.

**Files:**
- Create: `trnscrb/App/StatusBarDropView.swift`

### Step 1: Create StatusBarDropView

Create `trnscrb/App/StatusBarDropView.swift`:

```swift
import AppKit

/// Transparent drop target overlaid on the status bar button.
///
/// Accepts file URL drops, validates against `FileType.allSupported`,
/// and forwards valid URLs to the provided callback. Does not interfere
/// with click handling — only drag-and-drop events are intercepted.
final class StatusBarDropView: NSView {
    /// Called with validated file URLs when a drop is accepted.
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasValidFiles(sender) else { return [] }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasValidFiles(sender) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls: [URL] = extractFileURLs(from: sender), !urls.isEmpty else {
            return false
        }
        let supported: [URL] = urls.filter {
            FileType.allSupported.contains($0.pathExtension.lowercased())
        }
        guard !supported.isEmpty else { return false }
        onDrop?(supported)
        return true
    }

    // MARK: - Pass through mouse events to the button underneath

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    // MARK: - Private

    /// Checks whether the drag contains at least one supported file.
    private func hasValidFiles(_ sender: NSDraggingInfo) -> Bool {
        guard let urls: [URL] = extractFileURLs(from: sender) else { return false }
        return urls.contains { FileType.allSupported.contains($0.pathExtension.lowercased()) }
    }

    /// Extracts file URLs from a dragging info pasteboard.
    private func extractFileURLs(from sender: NSDraggingInfo) -> [URL]? {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }
}
```

**Key design choice:** `hitTest(_:)` returns `nil` so mouse clicks pass through to the `NSStatusBarButton` underneath. Only drag events (which use `NSDraggingDestination` protocol, not hit testing) are intercepted. This means the button's click-to-toggle-popover still works.

### Step 2: Build and verify

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` — everything compiles.

### Step 3: Run all tests

Run: `swift test 2>&1 | tail -10`
Expected: all tests pass.

### Step 4: Commit

```bash
git add trnscrb/App/StatusBarDropView.swift \
  trnscrb/Presentation/Popover/PopoverView.swift \
  trnscrb/App/AppDelegate.swift
git commit -m "feat: wire end-to-end pipeline with drag-and-drop on popover and menu bar icon"
```

---

## Verification Checklist

After all tasks, verify the full pipeline manually:

1. `swift build` — compiles cleanly
2. `swift test` — all tests pass
3. Run the app (`swift run` or from Xcode) and verify:
   - Menu bar icon appears
   - Clicking icon opens popover with drop zone
   - Settings panel opens/closes
   - Drop zone shows dashed border on drag hover
   - "Choose Files..." button opens file picker
   - Dragging a file onto the menu bar icon is accepted (visual feedback)
4. With S3 + Mistral configured, drop a test file and verify end-to-end processing

The following are **NOT in Phase 3 scope** (Phase 4):
- Retry logic (exponential backoff for S3, single retry for Mistral)
- `RetentionCleaner` (background timer for S3 cleanup)
- macOS notifications ("file ready", error alerts)
- Launch at login (`SMAppService`)
- Menu bar icon states (processing animation, error badge)
- Parallel batch processing with `TaskGroup`
