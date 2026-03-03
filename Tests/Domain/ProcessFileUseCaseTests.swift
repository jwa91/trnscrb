import Foundation
import Testing

@testable import trnscrb

/// Collects processing stages in a thread-safe way for test assertions.
private final class LockedStageRecorder: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var stages: [ProcessingStage] = []

    func append(_ stage: ProcessingStage) {
        lock.lock()
        stages.append(stage)
        lock.unlock()
    }

    func recordedStages() -> [ProcessingStage] {
        lock.lock()
        defer { lock.unlock() }
        return stages
    }
}

private final class LockedProgressRecorder: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var values: [Double] = []

    func append(_ value: Double) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

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
        let (useCase, storage, audioTranscriber, ocrTranscriber, delivery, _) = makeUseCase()
        let presignedURL: URL = URL(string: "https://s3.example.com/presigned")!
        await storage.setUploadResult(presignedURL)
        await audioTranscriber.setProcessResult("# Meeting Notes")

        let fileURL: URL = URL(filePath: "/tmp/meeting.mp3")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.sourceFileName == "meeting.mp3")
        #expect(result.sourceFileType == .audio)
        #expect(result.deliveryWarnings.isEmpty)
        #expect(result.presignedSourceURL == presignedURL)
        #expect(result.savedFileURL == nil)
        let uploadedKeys: [String] = await storage.recordedUploadedKeys()
        #expect(uploadedKeys.count == 1)
        #expect(uploadedKeys[0].hasPrefix("trnscrb/"))
        #expect(uploadedKeys[0].hasSuffix(".mp3"))
        let processedURLs: [URL] = await audioTranscriber.recordedProcessedURLs()
        #expect(processedURLs == [presignedURL])
        #expect(await ocrTranscriber.recordedProcessedURLs().isEmpty)
        let deliveredResults: [TranscriptionResult] = await delivery.recordedDeliveredResults()
        #expect(deliveredResults.count == 1)
    }

    @Test func processFileReturnsSavedFileMetadata() async throws {
        let presignedURL: URL = URL(string: "https://s3.example.com/presigned")!
        let savedFileURL: URL = URL(filePath: "/tmp/meeting.md")
        let storage: MockStorageGateway = MockStorageGateway(uploadResult: presignedURL)
        let delivery: MockDeliveryGateway = MockDeliveryGateway(savedFileURL: savedFileURL)
        let (useCase, _, _, _, _, _) = makeUseCase(storage: storage, delivery: delivery)

        let result: TranscriptionResult = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/meeting.mp3")
        )

        #expect(result.presignedSourceURL == presignedURL)
        #expect(result.savedFileURL == savedFileURL)
    }

    @Test func processPDFFile() async throws {
        let presignedURL: URL = URL(string: "https://s3.example.com/bucket/scan.pdf")!
        let storage: MockStorageGateway = MockStorageGateway(uploadResult: presignedURL)
        let (useCase, _, audioTranscriber, ocrTranscriber, _, _) = makeUseCase(storage: storage)
        await ocrTranscriber.setProcessResult("# Document")

        let fileURL: URL = URL(filePath: "/tmp/scan.pdf")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.sourceFileName == "scan.pdf")
        #expect(result.sourceFileType == .pdf)
        let processedURLs: [URL] = await ocrTranscriber.recordedProcessedURLs()
        #expect(processedURLs == [presignedURL])
        #expect(await audioTranscriber.recordedProcessedURLs().isEmpty)
    }

    @Test func processImageFile() async throws {
        let presignedURL: URL = URL(string: "https://s3.example.com/bucket/notes.png")!
        let storage: MockStorageGateway = MockStorageGateway(uploadResult: presignedURL)
        let (useCase, _, audioTranscriber, ocrTranscriber, _, _) = makeUseCase(storage: storage)
        await ocrTranscriber.setProcessResult("# Handwritten Note")

        let fileURL: URL = URL(filePath: "/tmp/notes.png")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.sourceFileName == "notes.png")
        #expect(result.sourceFileType == .image)
        let processedURLs: [URL] = await ocrTranscriber.recordedProcessedURLs()
        #expect(processedURLs == [presignedURL])
        #expect(await audioTranscriber.recordedProcessedURLs().isEmpty)
    }

    // MARK: - S3 key format

    @Test func s3KeyUsesPathPrefixAndUUIDAndExtension() async throws {
        let storage: MockStorageGateway = MockStorageGateway()
        let settings: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(s3PathPrefix: "custom/")
        )
        let (useCase, _, _, _, _, _) = makeUseCase(storage: storage, settings: settings)

        _ = try await useCase.execute(fileURL: URL(filePath: "/tmp/test.wav"))

        let key: String = await storage.recordedUploadedKeys()[0]
        #expect(key.hasPrefix("custom/"))
        #expect(key.hasSuffix(".wav"))
    }

    // MARK: - Stage changes

    @Test func reportsStageChangesInOrder() async throws {
        let (useCase, _, _, _, _, _) = makeUseCase()
        let recorder: LockedStageRecorder = LockedStageRecorder()

        _ = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/test.mp3")
        ) { stage in
            recorder.append(stage)
        }

        #expect(recorder.recordedStages() == [.uploading, .processing])
    }

    @Test func reportsUploadProgress() async throws {
        let (useCase, _, _, _, _, _) = makeUseCase()
        let recorder: LockedProgressRecorder = LockedProgressRecorder()

        _ = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/test.mp3"),
            onUploadProgress: { value in
                recorder.append(value)
            }
        )

        let progressValues: [Double] = recorder.snapshot()
        #expect(progressValues.first == 0)
        #expect(progressValues.last == 1)
    }

    @Test func retriesS3UploadAndEventuallySucceeds() async throws {
        let storage: MockStorageGateway = MockStorageGateway()
        await storage.setTransientUploadFailures(
            count: 2,
            error: S3Error.requestFailed(statusCode: 503, body: "Temporary")
        )
        let (useCase, _, _, _, _, _) = makeUseCase(storage: storage)

        _ = try await useCase.execute(fileURL: URL(filePath: "/tmp/retry.mp3"))

        #expect(await storage.recordedUploadAttemptCount() == 3)
    }

    @Test func retriesTranscriptionAndEventuallySucceeds() async throws {
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        await audio.setTransientProcessFailures(
            count: 1,
            error: MistralError.requestFailed(statusCode: 503, body: "Temporary")
        )
        let (useCase, _, _, _, _, _) = makeUseCase(audioTranscriber: audio)

        _ = try await useCase.execute(fileURL: URL(filePath: "/tmp/retry.mp3"))

        #expect(await audio.recordedProcessAttemptCount() == 2)
    }

    @Test func stopsAfterConfiguredS3RetryLimit() async throws {
        let storage: MockStorageGateway = MockStorageGateway()
        await storage.setTransientUploadFailures(
            count: 3,
            error: S3Error.requestFailed(statusCode: 503, body: "Still failing")
        )
        let (useCase, _, _, _, _, _) = makeUseCase(storage: storage)

        await #expect(throws: S3Error.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/retry.mp3"))
        }
        #expect(await storage.recordedUploadAttemptCount() == 3)
    }

    @Test func stopsAfterConfiguredTranscriptionRetryLimit() async throws {
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        await audio.setTransientProcessFailures(
            count: 2,
            error: MistralError.requestFailed(statusCode: 500, body: "Still failing")
        )
        let (useCase, _, _, _, _, _) = makeUseCase(audioTranscriber: audio)

        await #expect(throws: MistralError.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/retry.mp3"))
        }
        #expect(await audio.recordedProcessAttemptCount() == 2)
    }

    @Test func doesNotRetryOnNonRetriableS3RequestFailure() async throws {
        let storage: MockStorageGateway = MockStorageGateway()
        await storage.setUploadError(S3Error.requestFailed(statusCode: 400, body: "Bad request"))
        let (useCase, _, _, _, _, _) = makeUseCase(storage: storage)

        await #expect(throws: S3Error.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))
        }
        #expect(await storage.recordedUploadAttemptCount() == 1)
    }

    @Test func doesNotRetryOnLocalProviderError() async throws {
        let localAudio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions,
            providerMode: .localApple,
            sourceKind: .localFile,
            processError: LocalProviderError.noRecognizedContent
        )
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: MockStorageGateway(),
            transcribers: [localAudio],
            delivery: MockDeliveryGateway(),
            settings: MockSettingsGateway(settings: AppSettings(audioProviderMode: .localApple)),
            isLocalModeAvailable: { true }
        )

        await #expect(throws: LocalProviderError.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))
        }
        #expect(await localAudio.recordedProcessAttemptCount() == 1)
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
        await storage.setUploadError(S3Error.requestFailed(statusCode: 500, body: "Internal"))
        let (useCase, _, _, _, _, _) = makeUseCase(storage: storage)

        await #expect(throws: S3Error.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))
        }
    }

    @Test func propagatesTranscriptionError() async throws {
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        await audio.setProcessError(MistralError.requestFailed(statusCode: 500, body: "Error"))
        let (useCase, _, _, _, _, _) = makeUseCase(audioTranscriber: audio)

        await #expect(throws: MistralError.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))
        }
    }

    @Test func doesNotDeliverOnTranscriptionFailure() async throws {
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        await audio.setProcessError(MistralError.requestFailed(statusCode: 500, body: "Error"))
        let delivery: MockDeliveryGateway = MockDeliveryGateway()
        let (useCase, _, _, _, _, _) = makeUseCase(audioTranscriber: audio, delivery: delivery)

        _ = try? await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))

        #expect(await delivery.recordedDeliveredResults().isEmpty)
    }

    @Test func returnsDeliveryWarningsWhenOneDestinationFails() async throws {
        let delivery: MockDeliveryGateway = MockDeliveryGateway(
            deliverWarnings: ["Copied markdown to the clipboard, but saving the file failed."]
        )
        let (useCase, _, _, _, _, _) = makeUseCase(delivery: delivery)

        let result: TranscriptionResult = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/test.mp3")
        )

        #expect(result.deliveryWarnings == ["Copied markdown to the clipboard, but saving the file failed."])
    }

    // MARK: - Extension case insensitivity

    @Test func handlesUppercaseExtension() async throws {
        let (useCase, _, _, _, _, _) = makeUseCase()

        let result: TranscriptionResult = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/photo.JPEG")
        )

        #expect(result.sourceFileType == .image)
    }

    @Test func usesLocalProviderForConfiguredMediaWithoutUploading() async throws {
        let storage: MockStorageGateway = MockStorageGateway()
        let settings: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(audioProviderMode: .localApple)
        )
        let localAudio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions,
            providerMode: .localApple,
            sourceKind: .localFile,
            processResult: "# Local Audio"
        )
        let mistralAudio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions,
            providerMode: .mistral,
            sourceKind: .remoteURL,
            processResult: "# Cloud Audio"
        )
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: storage,
            transcribers: [mistralAudio, localAudio],
            delivery: MockDeliveryGateway(),
            settings: settings,
            isLocalModeAvailable: { true }
        )

        let fileURL: URL = URL(filePath: "/tmp/local-source.mp3")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.markdown == "# Local Audio")
        #expect(result.presignedSourceURL == nil)
        #expect(await storage.recordedUploadAttemptCount() == 0)
        #expect(await localAudio.recordedProcessedURLs() == [fileURL])
        #expect(await mistralAudio.recordedProcessedURLs().isEmpty)
    }

    @Test func fallsBackToMistralWhenLocalModeUnavailable() async throws {
        let storage: MockStorageGateway = MockStorageGateway(
            uploadResult: URL(string: "https://s3.example.com/presigned")!
        )
        let settings: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(audioProviderMode: .localApple)
        )
        let localAudio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions,
            providerMode: .localApple,
            sourceKind: .localFile,
            processResult: "# Local Audio"
        )
        let mistralAudio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions,
            providerMode: .mistral,
            sourceKind: .remoteURL,
            processResult: "# Cloud Audio"
        )
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: storage,
            transcribers: [mistralAudio, localAudio],
            delivery: MockDeliveryGateway(),
            settings: settings,
            isLocalModeAvailable: { false }
        )

        let result: TranscriptionResult = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/fallback.mp3")
        )

        #expect(result.markdown == "# Cloud Audio")
        #expect(await storage.recordedUploadAttemptCount() == 1)
        #expect(await localAudio.recordedProcessedURLs().isEmpty)
        #expect(await mistralAudio.recordedProcessedURLs() == [URL(string: "https://s3.example.com/presigned")!])
    }

    @Test func usesLocalProviderForConfiguredPDFWithoutUploading() async throws {
        let storage: MockStorageGateway = MockStorageGateway()
        let settings: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(pdfProviderMode: .localApple)
        )
        let localOCR: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions),
            providerMode: .localApple,
            sourceKind: .localFile,
            processResult: "# Local PDF"
        )
        let mistralOCR: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions),
            providerMode: .mistral,
            sourceKind: .remoteURL,
            processResult: "# Cloud PDF"
        )
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: storage,
            transcribers: [mistralOCR, localOCR],
            delivery: MockDeliveryGateway(),
            settings: settings,
            isLocalModeAvailable: { true }
        )

        let fileURL: URL = URL(filePath: "/tmp/local-source.pdf")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.sourceFileType == .pdf)
        #expect(result.presignedSourceURL == nil)
        #expect(await storage.recordedUploadAttemptCount() == 0)
        #expect(await localOCR.recordedProcessedURLs() == [fileURL])
        #expect(await mistralOCR.recordedProcessedURLs().isEmpty)
    }

    @Test func usesLocalProviderForConfiguredImageWithoutUploading() async throws {
        let storage: MockStorageGateway = MockStorageGateway()
        let settings: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(imageProviderMode: .localApple)
        )
        let localOCR: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions),
            providerMode: .localApple,
            sourceKind: .localFile,
            processResult: "# Local Image"
        )
        let mistralOCR: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions),
            providerMode: .mistral,
            sourceKind: .remoteURL,
            processResult: "# Cloud Image"
        )
        let useCase: ProcessFileUseCase = ProcessFileUseCase(
            storage: storage,
            transcribers: [mistralOCR, localOCR],
            delivery: MockDeliveryGateway(),
            settings: settings,
            isLocalModeAvailable: { true }
        )

        let fileURL: URL = URL(filePath: "/tmp/local-source.png")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.sourceFileType == .image)
        #expect(result.presignedSourceURL == nil)
        #expect(await storage.recordedUploadAttemptCount() == 0)
        #expect(await localOCR.recordedProcessedURLs() == [fileURL])
        #expect(await mistralOCR.recordedProcessedURLs().isEmpty)
    }
}
