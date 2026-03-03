import Foundation
import Testing

@testable import trnscrb

struct AppleSpeechAnalyzerProviderTests {
    @Test func processRequiresLocalFileURL() async {
        let provider: AppleSpeechAnalyzerProvider = AppleSpeechAnalyzerProvider()
        let remoteURL: URL = URL(string: "https://example.com/audio.mp3")!

        do {
            _ = try await provider.process(sourceURL: remoteURL)
            Issue.record("Expected local file validation error")
        } catch let error as LocalProviderError {
            #expect(error == .localFileRequired)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func processThrowsUnavailableErrorWhenLocalModeSupportIsDisabled() async {
        let provider: AppleSpeechAnalyzerProvider = AppleSpeechAnalyzerProvider(
            isLocalModeAvailable: { false }
        )
        do {
            _ = try await provider.process(sourceURL: URL(filePath: "/tmp/audio.mp3"))
            Issue.record("Expected unavailable error")
        } catch let error as LocalProviderError {
            #expect(error == .localModeUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
