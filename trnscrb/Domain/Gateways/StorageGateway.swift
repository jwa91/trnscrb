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
    /// - Returns: A presigned URL accessible by external services.
    func upload(fileURL: URL, key: String) async throws -> URL

    /// Deletes an object from storage.
    /// - Parameter key: Object key to delete.
    func delete(key: String) async throws

    /// Lists object keys that have exceeded the retention period.
    /// - Parameter retentionHours: Maximum age in hours before an object is expired.
    /// - Returns: Keys of expired objects.
    func listExpired(retentionHours: Int) async throws -> [String]
}
