import Foundation

@testable import trnscrb

actor MockTranscriptionGateway: TranscriptionGateway {
    let providerMode: ProviderMode
    let supportedSourceKinds: Set<TranscriptionSourceKind>
    let supportedExtensions: Set<String>
    /// Markdown returned by process.
    private var processResult: String
    /// If set, process throws this error.
    private var processError: (any Error & Sendable)?
    /// Transient processing error retried for a fixed number of attempts.
    private var transientProcessError: (any Error & Sendable)?
    private var transientProcessFailuresRemaining: Int
    /// Optional artificial delay to make async behavior deterministic in tests.
    private var processingDelay: Duration?
    /// Records URLs passed to process.
    private var processedURLs: [URL]
    private var processAttemptCount: Int

    init(
        supportedExtensions: Set<String>,
        providerMode: ProviderMode = .mistral,
        supportedSourceKinds: Set<TranscriptionSourceKind> = [.remoteURL],
        processResult: String = "# Transcribed",
        processError: (any Error & Sendable)? = nil,
        processingDelay: Duration? = nil
    ) {
        self.providerMode = providerMode
        self.supportedSourceKinds = supportedSourceKinds
        self.supportedExtensions = supportedExtensions
        self.processResult = processResult
        self.processError = processError
        self.transientProcessError = nil
        self.transientProcessFailuresRemaining = 0
        self.processingDelay = processingDelay
        self.processedURLs = []
        self.processAttemptCount = 0
    }

    init(
        supportedExtensions: Set<String>,
        providerMode: ProviderMode = .mistral,
        sourceKind: TranscriptionSourceKind,
        processResult: String = "# Transcribed",
        processError: (any Error & Sendable)? = nil,
        processingDelay: Duration? = nil
    ) {
        self.providerMode = providerMode
        self.supportedSourceKinds = [sourceKind]
        self.supportedExtensions = supportedExtensions
        self.processResult = processResult
        self.processError = processError
        self.transientProcessError = nil
        self.transientProcessFailuresRemaining = 0
        self.processingDelay = processingDelay
        self.processedURLs = []
        self.processAttemptCount = 0
    }

    func setProcessResult(_ result: String) {
        processResult = result
    }

    func setProcessError(_ error: (any Error & Sendable)?) {
        processError = error
    }

    func setTransientProcessFailures(
        count: Int,
        error: (any Error & Sendable)
    ) {
        transientProcessFailuresRemaining = max(0, count)
        transientProcessError = error
    }

    func setProcessingDelay(_ delay: Duration?) {
        processingDelay = delay
    }

    func recordedProcessedURLs() -> [URL] {
        processedURLs
    }

    func recordedProcessAttemptCount() -> Int {
        processAttemptCount
    }

    func process(sourceURL: URL) async throws -> String {
        processAttemptCount += 1
        if let processingDelay {
            try await Task.sleep(for: processingDelay)
        }
        if transientProcessFailuresRemaining > 0 {
            transientProcessFailuresRemaining -= 1
            throw transientProcessError ?? MistralError.requestFailed(statusCode: 500, body: "Transient")
        }
        if let processError {
            throw processError
        }
        processedURLs.append(sourceURL)
        return processResult
    }
}
