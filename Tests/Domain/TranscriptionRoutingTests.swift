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
            transcribers: [mistralAudio, localAudio]
        )

        #expect(route.effectiveMode == .localApple)
        #expect(route.transcriber.providerMode == .localApple)
        #expect(route.transcriber.sourceKind == .localFile)
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
                transcribers: [mistralAudio]
            )
        }
    }
}
