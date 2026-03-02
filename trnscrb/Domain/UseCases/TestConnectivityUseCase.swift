import Foundation

/// Coordinates settings connectivity checks through a domain-owned gateway.
public struct TestConnectivityUseCase: Sendable {
    private let gateway: any ConnectivityGateway

    public init(gateway: any ConnectivityGateway) {
        self.gateway = gateway
    }

    public func testS3(settings: AppSettings, s3SecretKey: String) async throws {
        try await gateway.testS3(settings: settings, s3SecretKey: s3SecretKey)
    }

    public func testMistral(apiKey: String) async throws {
        try await gateway.testMistral(apiKey: apiKey)
    }
}
