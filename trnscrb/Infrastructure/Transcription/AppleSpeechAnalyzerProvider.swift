import Foundation
import Speech

/// Transcribes local audio files using Apple's on-device speech stack.
///
/// This provider is intentionally gated to macOS 26+ so local mode remains
/// a Tahoe-only feature in the app.
public struct AppleSpeechAnalyzerProvider: TranscriptionGateway {
    public let providerMode: ProviderMode = .localApple
    public let sourceKind: TranscriptionSourceKind = .localFile
    public var supportedExtensions: Set<String> { FileType.audioExtensions }

    private let locale: Locale

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    public func process(sourceURL: URL) async throws -> String {
        guard sourceURL.isFileURL else {
            throw LocalProviderError.localFileRequired
        }
        guard #available(macOS 26, *) else {
            throw LocalProviderError.localModeUnavailable
        }

        try await ensureSpeechAuthorization()

        guard let recognizer: SFSpeechRecognizer = SFSpeechRecognizer(locale: locale) else {
            throw LocalProviderError.transcriptionFailed("Speech recognizer unavailable for locale \(locale.identifier).")
        }

        let request: SFSpeechURLRecognitionRequest = SFSpeechURLRecognitionRequest(url: sourceURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        let transcript: String = try await recognize(
            recognizer: recognizer,
            request: request
        )
        let normalizedTranscript: String = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTranscript.isEmpty else {
            throw LocalProviderError.noRecognizedContent
        }
        return normalizedTranscript
    }

    private func ensureSpeechAuthorization() async throws {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                continuation.resume(returning: newStatus)
            }
        }
        guard status == .authorized else {
            throw LocalProviderError.speechAuthorizationDenied
        }
    }

    private func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let lock: NSLock = NSLock()
            var didResume: Bool = false
            let taskBox: SpeechRecognitionTaskBox = SpeechRecognitionTaskBox()

            func beginResume() -> Bool {
                lock.lock()
                let shouldResume: Bool = !didResume
                if shouldResume {
                    didResume = true
                }
                lock.unlock()
                return shouldResume
            }

            func resumeFailure(_ message: String) {
                guard beginResume() else { return }
                continuation.resume(throwing: LocalProviderError.transcriptionFailed(message))
            }

            func resumeSuccess(_ transcript: String) {
                guard beginResume() else { return }
                continuation.resume(returning: transcript)
            }

            taskBox.task = recognizer.recognitionTask(with: request) { [taskBox] result, error in
                _ = taskBox
                if let error {
                    resumeFailure(error.localizedDescription)
                    return
                }
                guard let result else { return }
                if result.isFinal {
                    resumeSuccess(result.bestTranscription.formattedString)
                }
            }
        }
    }
}

private final class SpeechRecognitionTaskBox: @unchecked Sendable {
    var task: SFSpeechRecognitionTask?

    deinit {
        task?.cancel()
    }
}
