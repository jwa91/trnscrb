import Foundation

@testable import trnscrb

actor MockStorageGateway: StorageGateway {
    /// URL returned by upload.
    private var uploadResult: URL
    /// If set, upload throws this error.
    private var uploadError: (any Error & Sendable)?
    /// Transient upload error retried for a fixed number of attempts.
    private var transientUploadError: (any Error & Sendable)?
    private var transientUploadFailuresRemaining: Int
    /// Records uploaded keys.
    private var uploadedKeys: [String]
    private var uploadAttemptCount: Int

    init(
        uploadResult: URL = URL(string: "https://s3.example.com/bucket/file.mp3")!,
        uploadError: (any Error & Sendable)? = nil
    ) {
        self.uploadResult = uploadResult
        self.uploadError = uploadError
        self.transientUploadError = nil
        self.transientUploadFailuresRemaining = 0
        self.uploadedKeys = []
        self.uploadAttemptCount = 0
    }

    func setUploadResult(_ result: URL) {
        uploadResult = result
    }

    func setUploadError(_ error: (any Error & Sendable)?) {
        uploadError = error
    }

    func setTransientUploadFailures(
        count: Int,
        error: (any Error & Sendable)
    ) {
        transientUploadFailuresRemaining = max(0, count)
        transientUploadError = error
    }

    func recordedUploadedKeys() -> [String] {
        uploadedKeys
    }

    func recordedUploadAttemptCount() -> Int {
        uploadAttemptCount
    }

    func upload(
        fileURL _: URL,
        key: String,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        uploadAttemptCount += 1
        onProgress?(0)
        if transientUploadFailuresRemaining > 0 {
            transientUploadFailuresRemaining -= 1
            throw transientUploadError ?? S3Error.requestFailed(statusCode: 500, body: "Transient")
        }
        if let uploadError {
            throw uploadError
        }
        uploadedKeys.append(key)
        onProgress?(1)
        return uploadResult
    }

    func delete(key: String) async throws {}
    func listCreatedBefore(_ cutoff: Date) async throws -> [String] { [] }
}
