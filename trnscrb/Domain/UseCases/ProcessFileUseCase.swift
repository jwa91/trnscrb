import Foundation

/// Errors from the file processing pipeline.
public enum ProcessFileError: Error, Sendable, Equatable {
    /// The file extension is not supported by any provider.
    case unsupportedFileType(String)
    /// The input file remained empty while waiting for a provider-backed export.
    case emptyInputFile(String)
}

extension ProcessFileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: .\(ext)"
        case .emptyInputFile(let fileName):
            return "Input file is empty or still being prepared: \(fileName)"
        }
    }
}

/// Stages of the processing pipeline, reported via callback.
public enum ProcessingStage: Sendable, Equatable {
    /// Transcription/OCR work is in progress.
    case processing
    /// Optional S3 mirroring is in progress.
    case mirroring
    /// Result delivery is in progress.
    case delivery
}

/// Orchestrates the full file processing pipeline: prepare -> transcribe -> optional mirror -> deliver.
///
/// This is the core use case. It:
/// 1. Validates the file extension and determines the file type
/// 2. Finds the right `TranscriptionGateway` for the file type
/// 3. Prepares the best available processing source for that transcriber
/// 4. Calls the transcription/OCR API
/// 5. Optionally mirrors the original file to S3-compatible storage
/// 6. Delivers the markdown result via `DeliveryGateway`
public final class ProcessFileUseCase: Sendable {
    /// Object storage for uploading files.
    private let storage: any StorageGateway
    /// Available transcription/OCR providers (matched by file extension).
    private let transcribers: [any TranscriptionGateway]
    /// Delivers results to the user (clipboard, file, or both).
    private let delivery: any DeliveryGateway
    /// Settings for S3 path prefix and other config.
    private let settings: any SettingsGateway
    /// Injectable sleep used only for retry backoff scheduling.
    private let retrySleep: @Sendable (UInt64) async throws -> Void

    /// Creates the use case with injected dependencies.
    public init(
        storage: any StorageGateway,
        transcribers: [any TranscriptionGateway],
        delivery: any DeliveryGateway,
        settings: any SettingsGateway,
        retrySleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.storage = storage
        self.transcribers = transcribers
        self.delivery = delivery
        self.settings = settings
        self.retrySleep = retrySleep
    }

    /// Processes a dropped file end-to-end.
    /// - Parameters:
    ///   - fileURL: Local path to the file.
    ///   - onStageChange: Optional callback reporting pipeline stage transitions.
    ///   - onMirroringProgress: Optional callback with mirroring progress in 0...1.
    /// - Returns: The transcription result with markdown content.
    public func execute(
        fileURL: URL,
        onStageChange: (@Sendable (ProcessingStage) -> Void)? = nil,
        onMirroringProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TranscriptionResult {
        try await waitForInputFileIfNeeded(fileURL)

        let ext: String = fileURL.pathExtension.lowercased()
        AppLog.pipeline.info("Starting process for \(fileURL.lastPathComponent, privacy: .public)")

        guard let fileType: FileType = FileType.from(extension: ext) else {
            AppLog.pipeline.error("Unsupported file type \(ext, privacy: .public)")
            throw ProcessFileError.unsupportedFileType(ext)
        }

        let appSettings: AppSettings = try await settings.loadSettings().normalizedForUse
        let route: TranscriptionRoute
        do {
            route = try TranscriptionRouting.resolve(
                fileType: fileType,
                fileExtension: ext,
                settings: appSettings,
                transcribers: transcribers
            )
        } catch is TranscriptionRoutingError {
            throw ProcessFileError.unsupportedFileType(ext)
        }
        onStageChange?(.processing)
        let preparedSource: PreparedSource = try await prepareSource(
            fileURL: fileURL,
            fileExtension: ext,
            appSettings: appSettings,
            transcriber: route.transcriber
        )
        let sourceURL: URL = preparedSource.processingURL
        var remoteSourceURL: URL? = preparedSource.remoteSourceURL

        AppLog.pipeline.info(
            "Calling transcriber for \(fileURL.lastPathComponent, privacy: .public) as \(String(describing: fileType), privacy: .public) in \(route.effectiveMode.rawValue, privacy: .public) mode"
        )
        let transcriptionStartedAt: Date = Date()
        let markdown: String = try await retry(
            operationName: "transcription",
            maxAttempts: 2,
            initialBackoffNanoseconds: 500_000_000
        ) {
            try await route.transcriber.process(sourceURL: sourceURL)
        }
        let transcriptionElapsedMs: Int = Int((Date().timeIntervalSince(transcriptionStartedAt) * 1000).rounded())
        AppLog.pipeline.info("Transcriber completed for \(fileURL.lastPathComponent, privacy: .public) in \(transcriptionElapsedMs, privacy: .public) ms")

        let result: TranscriptionResult = TranscriptionResult(
            markdown: markdown,
            sourceFileName: fileURL.lastPathComponent,
            sourceFileType: fileType
        )

        var mirrorWarnings: [String] = []
        if preparedSource.requiresMirroringUpload {
            do {
                onStageChange?(.mirroring)
                remoteSourceURL = try await mirrorSourceFile(
                    fileURL: fileURL,
                    fileExtension: ext,
                    appSettings: appSettings,
                    onMirroringProgress: onMirroringProgress
                )
            } catch {
                let warning: String = mirrorWarningMessage(for: error)
                mirrorWarnings = [warning]
                AppLog.pipeline.error(
                    "Mirroring failed for \(fileURL.lastPathComponent, privacy: .public): \(warning, privacy: .public)"
                )
            }
        }

        onStageChange?(.delivery)
        AppLog.pipeline.info("Starting delivery for \(fileURL.lastPathComponent, privacy: .public)")
        let deliveryStartedAt: Date = Date()
        let deliveryReport: DeliveryReport = try await delivery.deliver(result: result)
        let deliveryElapsedMs: Int = Int((Date().timeIntervalSince(deliveryStartedAt) * 1000).rounded())
        AppLog.pipeline.info("Delivery completed for \(fileURL.lastPathComponent, privacy: .public) in \(deliveryElapsedMs, privacy: .public) ms")

        return TranscriptionResult(
            markdown: result.markdown,
            sourceFileName: result.sourceFileName,
            sourceFileType: result.sourceFileType,
            mirrorWarnings: mirrorWarnings,
            deliveryWarnings: deliveryReport.warnings,
            savedFileURL: deliveryReport.savedFileURL,
            remoteSourceURL: remoteSourceURL
        )
    }

    private func waitForInputFileIfNeeded(_ fileURL: URL) async throws {
        guard fileURL.isFileURL else { return }
        guard let initialFileSize = fileSize(of: fileURL) else { return }
        guard initialFileSize == 0 else { return }

        let waitSchedule: [UInt64] = [
            50_000_000,
            100_000_000,
            150_000_000,
            250_000_000,
            400_000_000,
            600_000_000,
            900_000_000
        ]

        var elapsedNanoseconds: UInt64 = 0
        for delay in waitSchedule {
            try await retrySleep(delay)
            elapsedNanoseconds += delay

            if let currentFileSize = fileSize(of: fileURL), currentFileSize > 0 {
                return
            }
        }

        throw ProcessFileError.emptyInputFile(fileURL.lastPathComponent)
    }

    private func prepareSource(
        fileURL: URL,
        fileExtension: String,
        appSettings: AppSettings,
        transcriber: any TranscriptionGateway
    ) async throws -> PreparedSource {
        let sourceKind: TranscriptionSourceKind = sourceKindForProcessing(transcriber: transcriber)

        switch sourceKind {
        case .localFile:
            return PreparedSource(
                processingURL: fileURL,
                remoteSourceURL: nil,
                requiresMirroringUpload: appSettings.bucketMirroringEnabled
            )
        case .remoteURL:
            let uploadedURL: URL = try await uploadSourceFile(
                fileURL: fileURL,
                fileExtension: fileExtension,
                appSettings: appSettings
            )
            return PreparedSource(
                processingURL: uploadedURL,
                remoteSourceURL: uploadedURL,
                requiresMirroringUpload: false
            )
        }
    }

    private func sourceKindForProcessing(transcriber: any TranscriptionGateway) -> TranscriptionSourceKind {
        let supportsRemoteURL: Bool = transcriber.supportedSourceKinds.contains(.remoteURL)
        let supportsLocalFile: Bool = transcriber.supportedSourceKinds.contains(.localFile)

        if supportsLocalFile {
            return .localFile
        }
        if supportsRemoteURL {
            return .remoteURL
        }
        return .localFile
    }

    private func uploadSourceFile(
        fileURL: URL,
        fileExtension: String,
        appSettings: AppSettings
    ) async throws -> URL {
        let key: String = "\(appSettings.s3PathPrefix)\(UUID().uuidString).\(fileExtension)"
        AppLog.pipeline.info("Uploading \(fileURL.lastPathComponent, privacy: .public) to key \(key, privacy: .public)")
        let uploadStartedAt: Date = Date()
        let uploadedURL: URL = try await retry(
            operationName: "upload",
            maxAttempts: 3,
            initialBackoffNanoseconds: 250_000_000
        ) {
            try await storage.upload(
                fileURL: fileURL,
                key: key,
                onProgress: nil
            )
        }
        let uploadElapsedMs: Int = Int((Date().timeIntervalSince(uploadStartedAt) * 1000).rounded())
        AppLog.pipeline.info("Upload complete for \(fileURL.lastPathComponent, privacy: .public) in \(uploadElapsedMs, privacy: .public) ms")
        return uploadedURL
    }

    private func mirrorSourceFile(
        fileURL: URL,
        fileExtension: String,
        appSettings: AppSettings,
        onMirroringProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        let key: String = "\(appSettings.s3PathPrefix)\(UUID().uuidString).\(fileExtension)"
        AppLog.pipeline.info("Mirroring \(fileURL.lastPathComponent, privacy: .public) to key \(key, privacy: .public)")
        let mirrorStartedAt: Date = Date()
        let mirroredURL: URL = try await retry(
            operationName: "mirroring",
            maxAttempts: 3,
            initialBackoffNanoseconds: 250_000_000
        ) {
            try await storage.upload(
                fileURL: fileURL,
                key: key,
                onProgress: onMirroringProgress
            )
        }
        let mirrorElapsedMs: Int = Int((Date().timeIntervalSince(mirrorStartedAt) * 1000).rounded())
        AppLog.pipeline.info("Mirroring complete for \(fileURL.lastPathComponent, privacy: .public) in \(mirrorElapsedMs, privacy: .public) ms")
        return mirroredURL
    }

    private func mirrorWarningMessage(for error: any Error) -> String {
        "Processed file successfully, but mirroring to S3 failed: \(error.localizedDescription)"
    }

    /// Retries an async operation with exponential backoff.
    private func retry<T>(
        operationName: String,
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
                    "\(operationName, privacy: .public) attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                guard attempt < maxAttempts, shouldRetry(error) else {
                    throw error
                }
                let delayMs: Int = Int(backoff / 1_000_000)
                AppLog.pipeline.info(
                    "Retrying \(operationName, privacy: .public) attempt \(attempt + 1, privacy: .public) after \(delayMs, privacy: .public) ms backoff"
                )
                try await retrySleep(backoff)
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

    private func fileSize(of url: URL) -> Int? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path())
        } catch {
            return nil
        }
        if let fileSize = attributes[.size] as? NSNumber {
            return fileSize.intValue
        }
        return attributes[.size] as? Int
    }
}

private struct PreparedSource {
    let processingURL: URL
    let remoteSourceURL: URL?
    let requiresMirroringUpload: Bool
}
