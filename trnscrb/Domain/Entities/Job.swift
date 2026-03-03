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
    /// Detected file type (audio, pdf, image).
    public let fileType: FileType
    /// Local URL of the dropped file.
    public let fileURL: URL
    /// Original file name, derived from `fileURL`.
    public var fileName: String { fileURL.lastPathComponent }
    /// Current processing state.
    public private(set) var status: JobStatus
    /// Markdown output, set on completion.
    public private(set) var markdown: String?
    /// Non-fatal warnings surfaced after successful completion.
    public private(set) var deliveryWarnings: [String]
    /// Local file URL when the markdown was saved to disk.
    public private(set) var savedFileURL: URL?
    /// Presigned source URL used for remote processing.
    public private(set) var presignedSourceURL: URL?
    /// When the job was created.
    public let createdAt: Date
    /// When the job completed or failed.
    public private(set) var completedAt: Date?

    /// Creates a new job in the `pending` state.
    public init(
        id: UUID = UUID(),
        fileType: FileType,
        fileURL: URL,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileType = fileType
        self.fileURL = fileURL
        self.status = .pending
        self.markdown = nil
        self.deliveryWarnings = []
        self.savedFileURL = nil
        self.presignedSourceURL = nil
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
    public mutating func complete(
        markdown: String,
        deliveryWarnings: [String] = [],
        savedFileURL: URL? = nil,
        presignedSourceURL: URL? = nil
    ) {
        guard case .processing = status else { return }
        self.markdown = markdown
        self.deliveryWarnings = deliveryWarnings
        self.savedFileURL = savedFileURL
        self.presignedSourceURL = presignedSourceURL
        self.status = .completed
        self.completedAt = Date()
    }

    /// Transitions to `failed` from any active state.
    public mutating func fail(error: String) {
        switch status {
        case .pending, .uploading, .processing:
            self.status = .failed(error: error)
            self.markdown = nil
            self.deliveryWarnings = []
            self.savedFileURL = nil
            self.presignedSourceURL = nil
            self.completedAt = Date()
        case .completed, .failed:
            break
        }
    }

    /// Requeues a job by returning it to the pending state.
    public mutating func requeue() {
        switch status {
        case .pending, .uploading, .processing, .failed:
            status = .pending
            markdown = nil
            deliveryWarnings = []
            savedFileURL = nil
            presignedSourceURL = nil
            completedAt = nil
        case .completed:
            break
        }
    }

    /// User-facing warning summary, if delivery completed with warnings.
    public var warningMessage: String? {
        guard !deliveryWarnings.isEmpty else { return nil }
        return deliveryWarnings.joined(separator: " ")
    }
}
