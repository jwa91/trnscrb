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
    ///   - onUploadProgress: Optional callback with upload progress in 0...1.
    /// - Returns: The transcription result with markdown content.
    public func execute(
        fileURL: URL,
        onStageChange: (@Sendable (ProcessingStage) -> Void)? = nil,
        onUploadProgress: (@Sendable (Double) -> Void)? = nil
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
        let presignedURL: URL = try await retry(
            maxAttempts: 3,
            initialBackoffNanoseconds: 250_000_000
        ) {
            try await storage.upload(
                fileURL: fileURL,
                key: key,
                onProgress: onUploadProgress
            )
        }

        onStageChange?(.processing)
        let markdown: String = try await retry(
            maxAttempts: 2,
            initialBackoffNanoseconds: 500_000_000
        ) {
            try await transcriber.process(sourceURL: presignedURL)
        }

        let result: TranscriptionResult = TranscriptionResult(
            markdown: markdown,
            sourceFileName: fileURL.lastPathComponent,
            sourceFileType: fileType
        )

        try await delivery.deliver(result: result)

        return result
    }

    /// Retries an async operation with exponential backoff.
    private func retry<T>(
        maxAttempts: Int,
        initialBackoffNanoseconds: UInt64,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        precondition(maxAttempts > 0, "maxAttempts must be > 0")
        var attempt: Int = 1
        var backoff: UInt64 = initialBackoffNanoseconds

        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < maxAttempts else {
                    throw error
                }
                try await Task.sleep(nanoseconds: backoff)
                attempt += 1
                backoff = min(backoff * 2, 5_000_000_000)
            }
        }
    }
}
