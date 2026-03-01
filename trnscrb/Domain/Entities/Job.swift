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
/// State machine: `pending -> uploading -> processing -> completed`
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
