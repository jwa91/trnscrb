import Foundation

@testable import trnscrb

final class MockStorageGateway: StorageGateway, @unchecked Sendable {
    /// URL returned by upload. Set before calling.
    var uploadResult: URL = URL(string: "https://s3.example.com/bucket/file.mp3")!
    /// If set, upload throws this error.
    var uploadError: (any Error)?
    /// Records uploaded keys.
    var uploadedKeys: [String] = []

    func upload(fileURL: URL, key: String) async throws -> URL {
        if let error = uploadError { throw error }
        uploadedKeys.append(key)
        return uploadResult
    }

    func delete(key: String) async throws {}
    func listCreatedBefore(_ cutoff: Date) async throws -> [String] { [] }
}
