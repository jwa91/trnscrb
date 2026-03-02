import Foundation

/// Abstracts object storage operations (S3-compatible).
///
/// The domain uses this to upload files and manage retention.
/// Concrete implementations provide the S3 specifics.
public protocol StorageGateway: Sendable {
    /// Uploads a local file to storage and returns a presigned URL.
    /// - Parameters:
    ///   - fileURL: Local file path to upload.
    ///   - key: Object key in the bucket (e.g., "trnscrb/abc123.mp3").
    ///   - onProgress: Optional upload progress callback (0...1).
    /// - Returns: A presigned URL accessible by external services.
    func upload(
        fileURL: URL,
        key: String,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL

    /// Deletes an object from storage.
    /// - Parameter key: Object key to delete.
    func delete(key: String) async throws

    /// Lists object keys created before the given cutoff date.
    /// - Parameter cutoff: Objects created before this date are considered expired.
    /// - Returns: Keys of expired objects.
    func listCreatedBefore(_ cutoff: Date) async throws -> [String]
}

public extension StorageGateway {
    /// Convenience overload when upload progress is not needed.
    func upload(fileURL: URL, key: String) async throws -> URL {
        try await upload(fileURL: fileURL, key: key, onProgress: nil)
    }
}
