import Foundation

/// Represents the processing state of a job.
public enum JobStatus: Sendable, Equatable {
    /// Job created, waiting to start.
    case pending
    /// Transcription/OCR work is in progress.
    case processing
    /// Optional S3 mirroring of the source file is in progress.
    case mirroring(progress: Double)
    /// Result delivery is in progress.
    case delivering
    /// Processing finished successfully.
    case completed
    /// Processing failed with an error message.
    case failed(error: String)
}

/// A single file processing job that tracks its lifecycle from drop to delivery.
///
/// State machine: `pending -> processing -> mirroring? -> delivering -> completed`
/// Failure is possible from any active stage.
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
    /// Non-fatal warnings surfaced after successful mirroring attempts.
    public private(set) var mirrorWarnings: [String]
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
        self.mirrorWarnings = []
        self.deliveryWarnings = []
        self.savedFileURL = nil
        self.presignedSourceURL = nil
        self.createdAt = createdAt
        self.completedAt = nil
    }

    /// Transitions from `pending` to `processing`.
    public mutating func startProcessing() {
        guard case .pending = status else { return }
        status = .processing
    }

    /// Transitions from `processing` to `mirroring`.
    public mutating func startMirroring() {
        guard case .processing = status else { return }
        status = .mirroring(progress: 0)
    }

    /// Updates mirroring progress (clamped to 0...1).
    public mutating func updateMirroringProgress(_ progress: Double) {
        guard case .mirroring = status else { return }
        status = .mirroring(progress: min(max(progress, 0), 1))
    }

    /// Transitions from an active work stage to `delivering`.
    public mutating func startDelivery() {
        switch status {
        case .processing, .mirroring:
            status = .delivering
        case .pending, .delivering, .completed, .failed:
            break
        }
    }

    /// Transitions from `delivering` to `completed` with markdown output.
    public mutating func complete(
        markdown: String,
        mirrorWarnings: [String] = [],
        deliveryWarnings: [String] = [],
        savedFileURL: URL? = nil,
        presignedSourceURL: URL? = nil
    ) {
        guard case .delivering = status else { return }
        self.markdown = markdown
        self.mirrorWarnings = mirrorWarnings
        self.deliveryWarnings = deliveryWarnings
        self.savedFileURL = savedFileURL
        self.presignedSourceURL = presignedSourceURL
        self.status = .completed
        self.completedAt = Date()
    }

    /// Transitions to `failed` from any active state.
    public mutating func fail(error: String) {
        switch status {
        case .pending, .processing, .mirroring, .delivering:
            self.status = .failed(error: error)
            self.markdown = nil
            self.mirrorWarnings = []
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
        case .pending, .processing, .mirroring, .delivering, .failed:
            status = .pending
            markdown = nil
            mirrorWarnings = []
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
        let warnings: [String] = mirrorWarnings + deliveryWarnings
        guard !warnings.isEmpty else { return nil }
        return warnings.joined(separator: " ")
    }
}
