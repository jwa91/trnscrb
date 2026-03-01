# Phase 0 — Project Scaffold Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a compilable Swift project with all domain types, gateway protocols, and use case signatures — the contracts that every later phase fills in.

**Architecture:** Clean Architecture with four layers (Domain, Infrastructure, Presentation, App). Domain is pure Swift (Foundation only). Gateway protocols are owned by the domain — dependency inversion. Infrastructure implements them. AppDelegate wires everything at the composition root.

**Tech Stack:** Swift 6 (strict concurrency by default), SwiftUI, macOS 14.0+, SPM, SwiftLint, Swift Testing

---

## Task 1: Project Setup

**Files:**
- Create: `Package.swift`
- Create: `.swiftlint.yml`
- Create: `.gitignore`
- Create: `trnscrb/App/TrnscrbrApp.swift`
- Create: directory tree per ARCHITECTURE.md

### Step 1: Create directory structure

```bash
cd /Users/jw/developer/trnscrb

# App source
mkdir -p trnscrb/App
mkdir -p trnscrb/Domain/Entities
mkdir -p trnscrb/Domain/UseCases
mkdir -p trnscrb/Domain/Gateways
mkdir -p trnscrb/Infrastructure/Storage
mkdir -p trnscrb/Infrastructure/Transcription
mkdir -p trnscrb/Infrastructure/Delivery
mkdir -p trnscrb/Infrastructure/Keychain
mkdir -p trnscrb/Infrastructure/Config
mkdir -p trnscrb/Presentation/ViewModels
mkdir -p trnscrb/Presentation/Popover
mkdir -p trnscrb/Presentation/Settings

# Tests
mkdir -p Tests/Domain
```

### Step 2: Create `.gitignore`

```gitignore
# Xcode
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/
*.xccheckout
*.moved-aside

# SPM
.build/
.swiftpm/
Package.resolved

# OS
.DS_Store

# SwiftLint
.swiftlint/
```

### Step 3: Create `Package.swift`

```swift
// swift-tools-version: 6.0

import PackageDescription

let package: Package = Package(
    name: "trnscrb",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "trnscrb",
            path: "trnscrb"
        ),
        .testTarget(
            name: "TrnscrbrTests",
            dependencies: ["trnscrb"],
            path: "Tests"
        ),
    ]
)
```

### Step 4: Create `.swiftlint.yml`

```yaml
# SwiftLint configuration for trnscrb
# Rules per HIGH-LEVEL-IMPLEMENTATION-STRATEGY.md

# Opt-in rules
opt_in_rules:
  - force_unwrapping
  - explicit_type_interface
  - missing_docs

# Hard errors — never allow these
force_cast:
  severity: error
force_try:
  severity: error
force_unwrapping:
  severity: error

# Require explicit types only on public declarations
explicit_type_interface:
  excluded:
    - local
    - internal
    - private
    - fileprivate
  allow_redundancy: true

# Require doc comments on public API
missing_docs:
  excludes_extensions: true
  excludes_inherited_types: true

# Length limits
file_length:
  warning: 400
  error: 500
function_body_length:
  warning: 40
  error: 80

# Naming
identifier_name:
  min_length: 2
  max_length: 60
  excluded:
    - id
    - s3

# Excluded paths
excluded:
  - .build
  - .swiftpm
  - Tests
```

### Step 5: Create minimal app entry point

Create `trnscrb/App/TrnscrbrApp.swift`:

```swift
import SwiftUI

/// Main entry point for the trnscrb menu bar app.
@main
struct TrnscrbrApp: App {
    var body: some Scene {
        MenuBarExtra("trnscrb", systemImage: "doc.text") {
            Text("trnscrb")
        }
    }
}
```

### Step 6: Verify the project builds

```bash
cd /Users/jw/developer/trnscrb && swift build 2>&1 | tail -5
```

Expected: `Build complete!`

### Step 7: Install SwiftLint and run it

```bash
brew install swiftlint
```

Then:

```bash
cd /Users/jw/developer/trnscrb && swiftlint lint --path trnscrb/ 2>&1
```

Expected: No errors (warnings are OK at this stage).

### Step 8: Commit

```bash
git add Package.swift .gitignore .swiftlint.yml trnscrb/App/TrnscrbrApp.swift
git commit -m "scaffold: init SPM project with directory structure and build config"
```

---

## Task 2: FileType Entity (TDD)

**Files:**
- Create: `Tests/Domain/FileTypeTests.swift`
- Create: `trnscrb/Domain/Entities/FileType.swift`

### Step 1: Write the failing test

Create `Tests/Domain/FileTypeTests.swift`:

```swift
import Testing

@testable import trnscrb

struct FileTypeTests {
    @Test func audioExtensions() {
        let audioExts: [String] = ["mp3", "wav", "m4a", "ogg", "flac", "webm", "mp4"]
        for ext in audioExts {
            #expect(FileType.from(extension: ext) == .audio, "Expected \(ext) to map to .audio")
        }
    }

    @Test func pdfExtension() {
        #expect(FileType.from(extension: "pdf") == .pdf)
    }

    @Test func imageExtensions() {
        let imageExts: [String] = ["png", "jpg", "jpeg", "heic", "tiff", "webp"]
        for ext in imageExts {
            #expect(FileType.from(extension: ext) == .image, "Expected \(ext) to map to .image")
        }
    }

    @Test func unsupportedExtensionReturnsNil() {
        #expect(FileType.from(extension: "xyz") == nil)
        #expect(FileType.from(extension: "doc") == nil)
        #expect(FileType.from(extension: "") == nil)
    }

    @Test func caseInsensitive() {
        #expect(FileType.from(extension: "MP3") == .audio)
        #expect(FileType.from(extension: "Pdf") == .pdf)
        #expect(FileType.from(extension: "PNG") == .image)
        #expect(FileType.from(extension: "HEIC") == .image)
    }

    @Test func allSupportedContainsEveryExtension() {
        let all: Set<String> = FileType.audioExtensions
            .union(FileType.pdfExtensions)
            .union(FileType.imageExtensions)
        #expect(FileType.allSupported == all)
    }
}
```

### Step 2: Run the test to verify it fails

```bash
cd /Users/jw/developer/trnscrb && swift test 2>&1 | tail -10
```

Expected: FAIL — `FileType` is not defined.

### Step 3: Write minimal implementation

Create `trnscrb/Domain/Entities/FileType.swift`:

```swift
import Foundation

/// Represents the category of a file being processed.
public enum FileType: Sendable, Equatable {
    /// Audio files (mp3, wav, m4a, ogg, flac, webm, mp4).
    case audio
    /// PDF documents.
    case pdf
    /// Image files (png, jpg, jpeg, heic, tiff, webp).
    case image

    /// File extensions accepted for audio transcription.
    public static let audioExtensions: Set<String> = [
        "mp3", "wav", "m4a", "ogg", "flac", "webm", "mp4",
    ]

    /// File extensions accepted for PDF processing.
    public static let pdfExtensions: Set<String> = ["pdf"]

    /// File extensions accepted for image OCR.
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tiff", "webp",
    ]

    /// All supported file extensions across all types.
    public static let allSupported: Set<String> =
        audioExtensions.union(pdfExtensions).union(imageExtensions)

    /// Determines the file type from a file extension.
    /// - Parameter ext: The file extension (without leading dot), case-insensitive.
    /// - Returns: The matching `FileType`, or `nil` if unsupported.
    public static func from(extension ext: String) -> FileType? {
        let lowered: String = ext.lowercased()
        if audioExtensions.contains(lowered) { return .audio }
        if pdfExtensions.contains(lowered) { return .pdf }
        if imageExtensions.contains(lowered) { return .image }
        return nil
    }
}
```

### Step 4: Run tests to verify they pass

```bash
cd /Users/jw/developer/trnscrb && swift test 2>&1 | tail -10
```

Expected: All tests pass.

### Step 5: Lint

```bash
cd /Users/jw/developer/trnscrb && swiftlint lint --path trnscrb/Domain/Entities/FileType.swift 2>&1
```

Expected: No errors.

### Step 6: Commit

```bash
git add trnscrb/Domain/Entities/FileType.swift Tests/Domain/FileTypeTests.swift
git commit -m "feat(domain): add FileType entity with extension routing"
```

---

## Task 3: Job Entity (TDD)

**Files:**
- Create: `Tests/Domain/JobTests.swift`
- Create: `trnscrb/Domain/Entities/Job.swift`

### Step 1: Write the failing test

Create `Tests/Domain/JobTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

struct JobStatusTests {
    @Test func initialStatusIsPending() {
        let job: Job = Job(
            fileName: "test.mp3",
            fileType: .audio,
            fileURL: URL(filePath: "/tmp/test.mp3")
        )
        #expect(job.status == .pending)
        #expect(job.markdown == nil)
        #expect(job.completedAt == nil)
    }
}

struct JobStateTransitionTests {
    private func makeJob() -> Job {
        Job(
            fileName: "recording.mp3",
            fileType: .audio,
            fileURL: URL(filePath: "/tmp/recording.mp3")
        )
    }

    // MARK: - Happy path: pending → uploading → processing → completed

    @Test func pendingToUploading() {
        var job: Job = makeJob()
        job.startUpload()
        #expect(job.status == .uploading(progress: 0))
    }

    @Test func uploadProgress() {
        var job: Job = makeJob()
        job.startUpload()
        job.updateUploadProgress(0.5)
        #expect(job.status == .uploading(progress: 0.5))
    }

    @Test func uploadProgressClampsTo0And1() {
        var job: Job = makeJob()
        job.startUpload()
        job.updateUploadProgress(-0.5)
        #expect(job.status == .uploading(progress: 0))
        job.updateUploadProgress(1.5)
        #expect(job.status == .uploading(progress: 1))
    }

    @Test func uploadingToProcessing() {
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        #expect(job.status == .processing)
    }

    @Test func processingToCompleted() {
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        job.complete(markdown: "# Hello")
        #expect(job.status == .completed)
        #expect(job.markdown == "# Hello")
        #expect(job.completedAt != nil)
    }

    // MARK: - Failure transitions

    @Test func pendingToFailed() {
        var job: Job = makeJob()
        job.fail(error: "Network offline")
        #expect(job.status == .failed(error: "Network offline"))
        #expect(job.completedAt != nil)
    }

    @Test func uploadingToFailed() {
        var job: Job = makeJob()
        job.startUpload()
        job.fail(error: "S3 upload failed")
        #expect(job.status == .failed(error: "S3 upload failed"))
    }

    @Test func processingToFailed() {
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        job.fail(error: "API error")
        #expect(job.status == .failed(error: "API error"))
    }

    // MARK: - Invalid transitions (no-ops)

    @Test func cannotSkipUploadingState() {
        var job: Job = makeJob()
        job.startProcessing()  // invalid: must upload first
        #expect(job.status == .pending)
    }

    @Test func cannotCompleteFromUploading() {
        var job: Job = makeJob()
        job.startUpload()
        job.complete(markdown: "nope")  // invalid: must process first
        #expect(job.status == .uploading(progress: 0))
        #expect(job.markdown == nil)
    }

    @Test func cannotFailFromCompleted() {
        var job: Job = makeJob()
        job.startUpload()
        job.startProcessing()
        job.complete(markdown: "# Done")
        job.fail(error: "too late")  // invalid: already completed
        #expect(job.status == .completed)
    }

    @Test func cannotFailFromAlreadyFailed() {
        var job: Job = makeJob()
        job.fail(error: "first error")
        job.fail(error: "second error")  // invalid: already failed
        #expect(job.status == .failed(error: "first error"))
    }
}

struct JobIdentityTests {
    @Test func uniqueIds() {
        let job1: Job = Job(
            fileName: "a.mp3", fileType: .audio, fileURL: URL(filePath: "/tmp/a.mp3"))
        let job2: Job = Job(
            fileName: "a.mp3", fileType: .audio, fileURL: URL(filePath: "/tmp/a.mp3"))
        #expect(job1.id != job2.id)
    }
}
```

### Step 2: Run tests to verify they fail

```bash
cd /Users/jw/developer/trnscrb && swift test 2>&1 | tail -10
```

Expected: FAIL — `Job` and `JobStatus` are not defined.

### Step 3: Write minimal implementation

Create `trnscrb/Domain/Entities/Job.swift`:

```swift
import Foundation

/// Represents the processing state of a job.
public enum JobStatus: Sendable, Equatable {
    /// Job created, waiting to start.
    case pending
    /// File is being uploaded to storage.
    case uploading(progress: Double)
    /// File uploaded, transcription/OCR in progress.
    case processing
    /// Processing finished successfully.
    case completed
    /// Processing failed with an error message.
    case failed(error: String)
}

/// A single file processing job that tracks its lifecycle from drop to delivery.
///
/// State machine: `pending → uploading → processing → completed`
/// Failure is possible from `pending`, `uploading`, or `processing`.
public struct Job: Sendable, Identifiable, Equatable {
    /// Unique identifier for this job.
    public let id: UUID
    /// Original file name (e.g., "meeting-recording.mp3").
    public let fileName: String
    /// Detected file type (audio, pdf, image).
    public let fileType: FileType
    /// Local URL of the dropped file.
    public let fileURL: URL
    /// Current processing state.
    public private(set) var status: JobStatus
    /// Markdown output, set on completion.
    public private(set) var markdown: String?
    /// When the job was created.
    public let createdAt: Date
    /// When the job completed or failed.
    public private(set) var completedAt: Date?

    /// Creates a new job in the `pending` state.
    public init(
        id: UUID = UUID(),
        fileName: String,
        fileType: FileType,
        fileURL: URL,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.fileType = fileType
        self.fileURL = fileURL
        self.status = .pending
        self.markdown = nil
        self.createdAt = createdAt
        self.completedAt = nil
    }

    /// Transitions from `pending` to `uploading`.
    public mutating func startUpload() {
        guard case .pending = status else { return }
        status = .uploading(progress: 0)
    }

    /// Updates upload progress (clamped to 0...1).
    public mutating func updateUploadProgress(_ progress: Double) {
        guard case .uploading = status else { return }
        status = .uploading(progress: min(max(progress, 0), 1))
    }

    /// Transitions from `uploading` to `processing`.
    public mutating func startProcessing() {
        guard case .uploading = status else { return }
        status = .processing
    }

    /// Transitions from `processing` to `completed` with markdown output.
    public mutating func complete(markdown: String) {
        guard case .processing = status else { return }
        self.markdown = markdown
        self.status = .completed
        self.completedAt = Date()
    }

    /// Transitions to `failed` from any active state.
    public mutating func fail(error: String) {
        switch status {
        case .pending, .uploading, .processing:
            self.status = .failed(error: error)
            self.completedAt = Date()
        case .completed, .failed:
            break
        }
    }
}
```

### Step 4: Run tests to verify they pass

```bash
cd /Users/jw/developer/trnscrb && swift test 2>&1 | tail -10
```

Expected: All tests pass.

### Step 5: Lint

```bash
cd /Users/jw/developer/trnscrb && swiftlint lint --path trnscrb/Domain/Entities/Job.swift 2>&1
```

Expected: No errors.

### Step 6: Commit

```bash
git add trnscrb/Domain/Entities/Job.swift Tests/Domain/JobTests.swift
git commit -m "feat(domain): add Job entity with state machine transitions"
```

---

## Task 4: TranscriptionResult + AppSettings

**Files:**
- Create: `trnscrb/Domain/Entities/TranscriptionResult.swift`
- Create: `trnscrb/Domain/Entities/AppSettings.swift`

### Step 1: Create TranscriptionResult

Create `trnscrb/Domain/Entities/TranscriptionResult.swift`:

```swift
import Foundation

/// The result of processing a file through the transcription/OCR pipeline.
public struct TranscriptionResult: Sendable, Equatable {
    /// The markdown content produced by transcription or OCR.
    public let markdown: String
    /// The original file name that was processed.
    public let sourceFileName: String
    /// The type of file that was processed.
    public let sourceFileType: FileType

    /// Creates a transcription result.
    public init(markdown: String, sourceFileName: String, sourceFileType: FileType) {
        self.markdown = markdown
        self.sourceFileName = sourceFileName
        self.sourceFileType = sourceFileType
    }
}
```

### Step 2: Create AppSettings and supporting types

Create `trnscrb/Domain/Entities/AppSettings.swift`:

```swift
import Foundation

/// How transcription results are delivered to the user.
public enum OutputMode: String, Sendable, Codable, Equatable {
    /// Copy markdown to clipboard and show notification.
    case clipboard
    /// Save markdown as .md file to output folder.
    case saveToFolder
    /// Both clipboard and file save.
    case both
}

/// Keys for secrets stored in the system keychain.
public enum SecretKey: String, Sendable {
    /// Mistral API key for transcription and OCR.
    case mistralAPIKey = "mistral-api-key"
    /// S3-compatible storage secret key.
    case s3SecretKey = "s3-secret-key"
}

/// Application settings persisted to the config file.
///
/// Secrets (API keys) are NOT part of this struct — they live in Keychain
/// and are accessed through `SettingsGateway` separately.
public struct AppSettings: Sendable, Equatable {
    /// S3-compatible endpoint URL (e.g., "https://nbg1.your-objectstorage.com").
    public var s3EndpointURL: String
    /// S3 access key identifier.
    public var s3AccessKey: String
    /// S3 bucket name.
    public var s3BucketName: String
    /// S3 region (default: "auto").
    public var s3Region: String
    /// Path prefix for uploaded objects (default: "trnscrb/").
    public var s3PathPrefix: String
    /// How results are delivered.
    public var outputMode: OutputMode
    /// Folder path for file save delivery.
    public var saveFolderPath: String
    /// Hours to retain files in S3 before cleanup.
    public var fileRetentionHours: Int
    /// Whether to launch at login.
    public var launchAtLogin: Bool

    /// Creates settings with defaults matching SPEC.md.
    public init(
        s3EndpointURL: String = "",
        s3AccessKey: String = "",
        s3BucketName: String = "",
        s3Region: String = "auto",
        s3PathPrefix: String = "trnscrb/",
        outputMode: OutputMode = .clipboard,
        saveFolderPath: String = "~/Documents/trnscrb/",
        fileRetentionHours: Int = 24,
        launchAtLogin: Bool = false
    ) {
        self.s3EndpointURL = s3EndpointURL
        self.s3AccessKey = s3AccessKey
        self.s3BucketName = s3BucketName
        self.s3Region = s3Region
        self.s3PathPrefix = s3PathPrefix
        self.outputMode = outputMode
        self.saveFolderPath = saveFolderPath
        self.fileRetentionHours = fileRetentionHours
        self.launchAtLogin = launchAtLogin
    }

    /// Whether the required S3 configuration fields are filled in.
    public var isS3Configured: Bool {
        !s3EndpointURL.isEmpty && !s3AccessKey.isEmpty && !s3BucketName.isEmpty
    }
}
```

### Step 3: Verify build and lint

```bash
cd /Users/jw/developer/trnscrb && swift build 2>&1 | tail -3
```

```bash
swiftlint lint --path trnscrb/Domain/Entities/ 2>&1
```

Expected: Build succeeds, no lint errors.

### Step 4: Commit

```bash
git add trnscrb/Domain/Entities/TranscriptionResult.swift trnscrb/Domain/Entities/AppSettings.swift
git commit -m "feat(domain): add TranscriptionResult, AppSettings, OutputMode, SecretKey"
```

---

## Task 5: Gateway Protocols

**Files:**
- Create: `trnscrb/Domain/Gateways/StorageGateway.swift`
- Create: `trnscrb/Domain/Gateways/TranscriptionGateway.swift`
- Create: `trnscrb/Domain/Gateways/DeliveryGateway.swift`
- Create: `trnscrb/Domain/Gateways/SettingsGateway.swift`

### Step 1: Create StorageGateway

Create `trnscrb/Domain/Gateways/StorageGateway.swift`:

```swift
import Foundation

/// Abstracts object storage operations (S3-compatible).
///
/// The domain uses this to upload files and manage retention.
/// Concrete implementations provide the S3 specifics.
public protocol StorageGateway: Sendable {
    /// Uploads a local file to storage and returns a presigned URL.
    /// - Parameters:
    ///   - fileURL: Local file path to upload.
    ///   - key: Object key in the bucket (e.g., "trnscrb/abc123.mp3").
    /// - Returns: A presigned URL accessible by external services.
    func upload(fileURL: URL, key: String) async throws -> URL

    /// Deletes an object from storage.
    /// - Parameter key: Object key to delete.
    func delete(key: String) async throws

    /// Lists object keys that have exceeded the retention period.
    /// - Parameter retentionHours: Maximum age in hours before an object is expired.
    /// - Returns: Keys of expired objects.
    func listExpired(retentionHours: Int) async throws -> [String]
}
```

### Step 2: Create TranscriptionGateway

Create `trnscrb/Domain/Gateways/TranscriptionGateway.swift`:

```swift
import Foundation

/// Abstracts transcription and OCR processing.
///
/// Both audio transcription (Voxtral) and document/image OCR conform
/// to this protocol. The `ProcessFileUseCase` routes by `FileType`
/// without knowing which API is called.
public protocol TranscriptionGateway: Sendable {
    /// The file extensions this provider can process.
    var supportedExtensions: Set<String> { get }

    /// Processes a file at the given URL and returns markdown.
    /// - Parameter sourceURL: Presigned URL pointing to the file in storage.
    /// - Returns: Markdown string produced by transcription or OCR.
    func process(sourceURL: URL) async throws -> String
}
```

### Step 3: Create DeliveryGateway

Create `trnscrb/Domain/Gateways/DeliveryGateway.swift`:

```swift
import Foundation

/// Abstracts delivery of transcription results to the user.
///
/// Concrete implementations: clipboard copy, file save, or both.
public protocol DeliveryGateway: Sendable {
    /// Delivers a transcription result to the user.
    /// - Parameter result: The completed transcription result.
    func deliver(result: TranscriptionResult) async throws
}
```

### Step 4: Create SettingsGateway

Create `trnscrb/Domain/Gateways/SettingsGateway.swift`:

```swift
import Foundation

/// Abstracts reading and writing application settings.
///
/// Config-file settings and keychain secrets are both accessed
/// through this single gateway — the domain doesn't know where
/// each value is stored.
public protocol SettingsGateway: Sendable {
    /// Loads application settings from persistent storage.
    func loadSettings() async throws -> AppSettings

    /// Saves application settings to persistent storage.
    func saveSettings(_ settings: AppSettings) async throws

    /// Retrieves a secret from secure storage.
    /// - Parameter key: Which secret to retrieve.
    /// - Returns: The secret value, or `nil` if not set.
    func getSecret(for key: SecretKey) async throws -> String?

    /// Stores a secret in secure storage.
    /// - Parameters:
    ///   - value: The secret value to store.
    ///   - key: Which secret to store.
    func setSecret(_ value: String, for key: SecretKey) async throws

    /// Removes a secret from secure storage.
    /// - Parameter key: Which secret to remove.
    func removeSecret(for key: SecretKey) async throws
}
```

### Step 5: Verify build and lint

```bash
cd /Users/jw/developer/trnscrb && swift build 2>&1 | tail -3
```

```bash
swiftlint lint --path trnscrb/Domain/Gateways/ 2>&1
```

Expected: Build succeeds, no lint errors.

### Step 6: Commit

```bash
git add trnscrb/Domain/Gateways/
git commit -m "feat(domain): add gateway protocols — Storage, Transcription, Delivery, Settings"
```

---

## Task 6: Use Case Signatures

**Files:**
- Create: `trnscrb/Domain/UseCases/ProcessFileUseCase.swift`
- Create: `trnscrb/Domain/UseCases/CleanupRetentionUseCase.swift`

### Step 1: Create ProcessFileUseCase

Create `trnscrb/Domain/UseCases/ProcessFileUseCase.swift`:

```swift
import Foundation

/// Orchestrates the full file processing pipeline: upload → transcribe → deliver.
///
/// This is the core use case. It:
/// 1. Uploads the dropped file to S3 via `StorageGateway`
/// 2. Finds the right `TranscriptionGateway` for the file type
/// 3. Calls the transcription/OCR API with the presigned URL
/// 4. Delivers the markdown result via `DeliveryGateway`
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
    /// - Parameter fileURL: Local path to the file.
    /// - Returns: The transcription result with markdown content.
    public func execute(fileURL: URL) async throws -> TranscriptionResult {
        fatalError("Implementation in Phase 3")
    }
}
```

### Step 2: Create CleanupRetentionUseCase

Create `trnscrb/Domain/UseCases/CleanupRetentionUseCase.swift`:

```swift
import Foundation

/// Deletes expired objects from S3 storage after the retention period.
///
/// Runs periodically in the background. Queries `StorageGateway` for
/// objects older than the configured retention hours and deletes them.
public final class CleanupRetentionUseCase: Sendable {
    /// Object storage to query and clean up.
    private let storage: any StorageGateway
    /// Settings for retention period configuration.
    private let settings: any SettingsGateway

    /// Creates the use case with injected dependencies.
    public init(
        storage: any StorageGateway,
        settings: any SettingsGateway
    ) {
        self.storage = storage
        self.settings = settings
    }

    /// Finds and deletes all expired S3 objects.
    public func execute() async throws {
        fatalError("Implementation in Phase 4")
    }
}
```

### Step 3: Verify build, tests, and lint

```bash
cd /Users/jw/developer/trnscrb && swift build 2>&1 | tail -3
```

```bash
cd /Users/jw/developer/trnscrb && swift test 2>&1 | tail -10
```

```bash
swiftlint lint --path trnscrb/ 2>&1
```

Expected: Build succeeds. All tests pass. No lint errors.

### Step 4: Commit

```bash
git add trnscrb/Domain/UseCases/
git commit -m "feat(domain): add ProcessFileUseCase and CleanupRetentionUseCase signatures"
```

---

## Final Verification Checklist

After all tasks are complete, verify:

```bash
# Clean build
cd /Users/jw/developer/trnscrb && swift build 2>&1 | tail -3

# All tests pass
swift test 2>&1 | tail -10

# No lint errors
swiftlint lint --path trnscrb/ 2>&1

# Project structure matches ARCHITECTURE.md
find trnscrb -name "*.swift" | sort
```

Expected file listing:

```
trnscrb/App/TrnscrbrApp.swift
trnscrb/Domain/Entities/AppSettings.swift
trnscrb/Domain/Entities/FileType.swift
trnscrb/Domain/Entities/Job.swift
trnscrb/Domain/Entities/TranscriptionResult.swift
trnscrb/Domain/Gateways/DeliveryGateway.swift
trnscrb/Domain/Gateways/SettingsGateway.swift
trnscrb/Domain/Gateways/StorageGateway.swift
trnscrb/Domain/Gateways/TranscriptionGateway.swift
trnscrb/Domain/UseCases/CleanupRetentionUseCase.swift
trnscrb/Domain/UseCases/ProcessFileUseCase.swift
```

Test files:

```
Tests/Domain/FileTypeTests.swift
Tests/Domain/JobTests.swift
```

**Phase 0 is complete when:**
- [x] All 11 Swift source files exist at the paths above
- [x] `swift build` succeeds with zero errors
- [x] `swift test` passes all FileType and Job tests
- [x] `swiftlint lint` reports zero errors on `trnscrb/`
- [x] Domain layer has zero imports of AppKit or SwiftUI (only Foundation)
- [x] Every `public` declaration has a doc comment
- [x] All entities are `Sendable`
- [x] Gateway protocols are `Sendable`
- [x] Use cases compile with `fatalError` placeholder bodies
