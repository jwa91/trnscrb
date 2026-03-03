import Foundation
import Testing

@testable import trnscrb

struct TranscriptionRoutingTests {
    @Test func selectsLocalProviderForConfiguredFileTypeWhenAvailable() throws {
        let localAudio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions,
            providerMode: .localApple,
            sourceKind: .localFile
        )
        let mistralAudio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions,
            providerMode: .mistral,
            sourceKind: .remoteURL
        )

        let route: TranscriptionRoute = try TranscriptionRouting.resolve(
            fileType: .audio,
            fileExtension: "mp3",
            settings: AppSettings(audioProviderMode: .localApple),
            transcribers: [mistralAudio, localAudio],
            isLocalModeAvailable: true
        )

        #expect(route.effectiveMode == .localApple)
        #expect(route.transcriber.providerMode == .localApple)
        #expect(route.transcriber.sourceKind == .localFile)
    }

    @Test func fallsBackToMistralWhenLocalModeIsUnavailable() throws {
        let localOCR: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions),
            providerMode: .localApple,
            sourceKind: .localFile
        )
        let mistralOCR: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.pdfExtensions.union(FileType.imageExtensions),
            providerMode: .mistral,
            sourceKind: .remoteURL
        )

        let route: TranscriptionRoute = try TranscriptionRouting.resolve(
            fileType: .pdf,
            fileExtension: "pdf",
            settings: AppSettings(pdfProviderMode: .localApple),
            transcribers: [localOCR, mistralOCR],
            isLocalModeAvailable: false
        )

        #expect(route.effectiveMode == .mistral)
        #expect(route.transcriber.providerMode == .mistral)
        #expect(route.transcriber.sourceKind == .remoteURL)
    }

    @Test func throwsWhenNoProviderMatchesEffectiveModeAndExtension() {
        let mistralAudio: MockTranscriptionGateway = MockTranscriptionGateway(
            supportedExtensions: FileType.audioExtensions,
            providerMode: .mistral,
            sourceKind: .remoteURL
        )

        #expect(throws: TranscriptionRoutingError.self) {
            _ = try TranscriptionRouting.resolve(
                fileType: .image,
                fileExtension: "png",
                settings: AppSettings(imageProviderMode: .localApple),
                transcribers: [mistralAudio],
                isLocalModeAvailable: true
            )
        }
    }
}
