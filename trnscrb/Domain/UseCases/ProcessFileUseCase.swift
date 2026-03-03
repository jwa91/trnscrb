import Foundation

/// Errors from the file processing pipeline.
public enum ProcessFileError: Error, Sendable, Equatable {
    /// The file extension is not supported by any provider.
    case unsupportedFileType(String)
}

extension ProcessFileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: .\(ext)"
        }
    }
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
        AppLog.pipeline.info("Starting process for \(fileURL.lastPathComponent, privacy: .public)")

        guard let fileType: FileType = FileType.from(extension: ext) else {
            AppLog.pipeline.error("Unsupported file type \(ext, privacy: .public)")
            throw ProcessFileError.unsupportedFileType(ext)
        }

        guard let transcriber = transcribers.first(
            where: { $0.supportedExtensions.contains(ext) }
        ) else {
            throw ProcessFileError.unsupportedFileType(ext)
        }

        let appSettings: AppSettings = try await settings.loadSettings().normalizedForUse
        let key: String = "\(appSettings.s3PathPrefix)\(UUID().uuidString).\(ext)"

        onStageChange?(.uploading)
        AppLog.pipeline.info("Uploading \(fileURL.lastPathComponent, privacy: .public) to key \(key, privacy: .public)")
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
        AppLog.pipeline.info("Upload complete for \(fileURL.lastPathComponent, privacy: .public)")

        onStageChange?(.processing)
        AppLog.pipeline.info("Calling transcriber for \(fileURL.lastPathComponent, privacy: .public) as \(String(describing: fileType), privacy: .public)")
        let markdown: String = try await retry(
            maxAttempts: 2,
            initialBackoffNanoseconds: 500_000_000
        ) {
            try await transcriber.process(sourceURL: presignedURL)
        }
        AppLog.pipeline.info("Transcriber completed for \(fileURL.lastPathComponent, privacy: .public)")

        let result: TranscriptionResult = TranscriptionResult(
            markdown: markdown,
            sourceFileName: fileURL.lastPathComponent,
            sourceFileType: fileType
        )

        let deliveryReport: DeliveryReport = try await delivery.deliver(result: result)
        AppLog.pipeline.info("Delivery completed for \(fileURL.lastPathComponent, privacy: .public)")

        return TranscriptionResult(
            markdown: result.markdown,
            sourceFileName: result.sourceFileName,
            sourceFileType: result.sourceFileType,
            deliveryWarnings: deliveryReport.warnings
        )
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
                AppLog.pipeline.error(
                    "Attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                guard attempt < maxAttempts, shouldRetry(error) else {
                    throw error
                }
                try await Task.sleep(nanoseconds: backoff)
                attempt += 1
                backoff = min(backoff * 2, 5_000_000_000)
            }
        }
    }

    private func shouldRetry(_ error: any Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .resourceUnavailable:
                return true
            default:
                return false
            }
        }

        if let s3Error = error as? S3Error {
            switch s3Error {
            case .invalidConfiguration:
                return false
            case .requestFailed(let statusCode, _):
                return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
            }
        }

        if let mistralError = error as? MistralError {
            switch mistralError {
            case .missingAPIKey, .invalidResponse:
                return false
            case .requestFailed(let statusCode, _):
                return statusCode == 408 || statusCode == 409 || statusCode == 429
                    || (500...599).contains(statusCode)
            }
        }

        return false
    }
}
