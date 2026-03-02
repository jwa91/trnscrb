import Foundation

@testable import trnscrb

final class MockTranscriptionGateway: TranscriptionGateway, @unchecked Sendable {
    let supportedExtensions: Set<String>
    /// Markdown returned by process. Set before calling.
    var processResult: String = "# Transcribed"
    /// If set, process throws this error.
    var processError: (any Error)?
    /// Records URLs passed to process.
    var processedURLs: [URL] = []

    init(supportedExtensions: Set<String>) {
        self.supportedExtensions = supportedExtensions
    }

    func process(sourceURL: URL) async throws -> String {
        if let error = processError { throw error }
        processedURLs.append(sourceURL)
        return processResult
    }
}
