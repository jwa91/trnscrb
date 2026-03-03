import Foundation
import Testing

@testable import trnscrb

/// Collects processing stages in a thread-safe way for test assertions.
private actor StageCollector {
    private var stages: [ProcessingStage] = []

    func append(_ stage: ProcessingStage) {
        stages.append(stage)
    }

    func recordedStages() -> [ProcessingStage] {
        stages
    }
}

private actor ProgressCollector {
    private var values: [Double] = []

    func append(_ value: Double) {
        values.append(value)
    }

    func snapshot() -> [Double] {
        values
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
        let (useCase, storage, audioTranscriber, _, delivery, _) = makeUseCase()
        let presignedURL: URL = URL(string: "https://s3.example.com/presigned")!
        await storage.setUploadResult(presignedURL)
        await audioTranscriber.setProcessResult("# Meeting Notes")

        let fileURL: URL = URL(filePath: "/tmp/meeting.mp3")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.markdown == "# Meeting Notes")
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
        let (useCase, _, _, ocrTranscriber, _, _) = makeUseCase()
        await ocrTranscriber.setProcessResult("# Document")

        let fileURL: URL = URL(filePath: "/tmp/scan.pdf")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.markdown == "# Document")
        #expect(result.sourceFileType == .pdf)
        let processedURLs: [URL] = await ocrTranscriber.recordedProcessedURLs()
        #expect(processedURLs.count == 1)
    }

    @Test func processImageFile() async throws {
        let (useCase, _, _, ocrTranscriber, _, _) = makeUseCase()
        await ocrTranscriber.setProcessResult("# Handwritten Note")

        let fileURL: URL = URL(filePath: "/tmp/notes.png")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.markdown == "# Handwritten Note")
        #expect(result.sourceFileType == .image)
        let processedURLs: [URL] = await ocrTranscriber.recordedProcessedURLs()
        #expect(processedURLs.count == 1)
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
        // UUID is 36 chars: 8-4-4-4-12. Key = "custom/" + UUID + ".wav" = 7 + 36 + 4 = 47
        #expect(key.count == 47)
    }

    // MARK: - Stage changes

    @Test func reportsStageChangesInOrder() async throws {
        let (useCase, _, _, _, _, _) = makeUseCase()
        let collector: StageCollector = StageCollector()

        _ = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/test.mp3")
        ) { stage in
            Task {
                await collector.append(stage)
            }
        }

        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(await collector.recordedStages() == [.uploading, .processing])
    }

    @Test func reportsUploadProgress() async throws {
        let (useCase, _, _, _, _, _) = makeUseCase()
        let collector: ProgressCollector = ProgressCollector()

        _ = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/test.mp3"),
            onUploadProgress: { value in
                Task {
                    await collector.append(value)
                }
            }
        )

        for _ in 0..<10 {
            await Task.yield()
        }
        let progressValues: [Double] = await collector.snapshot()
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
}
