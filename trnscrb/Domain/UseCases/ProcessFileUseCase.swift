import Foundation

/// Orchestrates the full file processing pipeline: upload -> transcribe -> deliver.
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
