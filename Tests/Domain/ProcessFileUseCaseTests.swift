import Foundation
import Testing

@testable import trnscrb

/// Collects processing stages in a thread-safe way for test assertions.
private final class StageCollector: @unchecked Sendable {
    var stages: [ProcessingStage] = []

    func append(_ stage: ProcessingStage) {
        stages.append(stage)
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
        storage.uploadResult = presignedURL
        audioTranscriber.processResult = "# Meeting Notes"

        let fileURL: URL = URL(filePath: "/tmp/meeting.mp3")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.markdown == "# Meeting Notes")
        #expect(result.sourceFileName == "meeting.mp3")
        #expect(result.sourceFileType == .audio)
        #expect(storage.uploadedKeys.count == 1)
        #expect(storage.uploadedKeys[0].hasPrefix("trnscrb/"))
        #expect(storage.uploadedKeys[0].hasSuffix(".mp3"))
        #expect(audioTranscriber.processedURLs == [presignedURL])
        #expect(delivery.deliveredResults.count == 1)
    }

    @Test func processPDFFile() async throws {
        let (useCase, _, _, ocrTranscriber, _, _) = makeUseCase()
        ocrTranscriber.processResult = "# Document"

        let fileURL: URL = URL(filePath: "/tmp/scan.pdf")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.markdown == "# Document")
        #expect(result.sourceFileType == .pdf)
        #expect(ocrTranscriber.processedURLs.count == 1)
    }

    @Test func processImageFile() async throws {
        let (useCase, _, _, ocrTranscriber, _, _) = makeUseCase()
        ocrTranscriber.processResult = "# Handwritten Note"

        let fileURL: URL = URL(filePath: "/tmp/notes.png")
        let result: TranscriptionResult = try await useCase.execute(fileURL: fileURL)

        #expect(result.markdown == "# Handwritten Note")
        #expect(result.sourceFileType == .image)
        #expect(ocrTranscriber.processedURLs.count == 1)
    }

    // MARK: - S3 key format

    @Test func s3KeyUsesPathPrefixAndUUIDAndExtension() async throws {
        let storage: MockStorageGateway = MockStorageGateway()
        let settings: MockSettingsGateway = MockSettingsGateway()
        settings.settings.s3PathPrefix = "custom/"
        let (useCase, _, _, _, _, _) = makeUseCase(storage: storage, settings: settings)

        _ = try await useCase.execute(fileURL: URL(filePath: "/tmp/test.wav"))

        let key: String = storage.uploadedKeys[0]
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
            collector.append(stage)
        }

        #expect(collector.stages == [.uploading, .processing])
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
        storage.uploadError = S3Error.requestFailed(statusCode: 500, body: "Internal")
        let (useCase, _, _, _, _, _) = makeUseCase(storage: storage)

        await #expect(throws: S3Error.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))
        }
    }

    @Test func propagatesTranscriptionError() async throws {
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        audio.processError = MistralError.requestFailed(statusCode: 500, body: "Error")
        let (useCase, _, _, _, _, _) = makeUseCase(audioTranscriber: audio)

        await #expect(throws: MistralError.self) {
            try await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))
        }
    }

    @Test func doesNotDeliverOnTranscriptionFailure() async throws {
        let audio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions
        )
        audio.processError = MistralError.requestFailed(statusCode: 500, body: "Error")
        let delivery: MockDeliveryGateway = MockDeliveryGateway()
        let (useCase, _, _, _, _, _) = makeUseCase(audioTranscriber: audio, delivery: delivery)

        _ = try? await useCase.execute(fileURL: URL(filePath: "/tmp/test.mp3"))

        #expect(delivery.deliveredResults.isEmpty)
    }

    // MARK: - Extension case insensitivity

    @Test func handlesUppercaseExtension() async throws {
        let (useCase, _, _, _, _, _) = makeUseCase()

        let result: TranscriptionResult = try await useCase.execute(
            fileURL: URL(filePath: "/tmp/photo.JPEG")
        )

        #expect(result.sourceFileType == .image)
    }
}
