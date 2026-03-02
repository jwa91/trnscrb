import Foundation

/// Abstracts connectivity checks used by settings validation UI actions.
public protocol ConnectivityGateway: Sendable {
    /// Validates S3 connectivity with the current form values.
    func testS3(settings: AppSettings, s3SecretKey: String) async throws

    /// Validates Mistral API connectivity using the provided key.
    func testMistral(apiKey: String) async throws
}
