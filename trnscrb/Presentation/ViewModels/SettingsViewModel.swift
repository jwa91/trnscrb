import Foundation

/// Result of a credential connectivity test.
public enum TestResult: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}

/// Bridges SettingsGateway to SwiftUI for the settings panel.
///
/// Loads settings and secrets, exposes them as published properties,
/// and saves changes back through the gateway.
@MainActor
public final class SettingsViewModel: ObservableObject {
    /// Current application settings.
    @Published public var settings: AppSettings = AppSettings()
    /// Mistral API key (stored in Keychain, not in AppSettings).
    @Published public var mistralAPIKey: String = ""
    /// S3 secret key (stored in Keychain, not in AppSettings).
    @Published public var s3SecretKey: String = ""
    /// Error message from the last failed operation, if any.
    @Published public var error: String?
    /// Result of the last S3 connectivity test.
    @Published public var s3TestResult: TestResult = .idle
    /// Result of the last Mistral API test.
    @Published public var mistralTestResult: TestResult = .idle

    /// Settings gateway for persistence.
    private let gateway: any SettingsGateway
    /// Domain use case for connectivity testing.
    private let connectivityUseCase: TestConnectivityUseCase

    /// Creates a view model backed by the given settings gateway.
    /// - Parameters:
    ///   - gateway: Settings persistence gateway.
    ///   - connectivityUseCase: Connectivity test use case.
    public init(gateway: any SettingsGateway, connectivityUseCase: TestConnectivityUseCase) {
        self.gateway = gateway
        self.connectivityUseCase = connectivityUseCase
    }

    /// Loads settings and secrets from persistent storage.
    public func load() async {
        do {
            settings = try await gateway.loadSettings()
            mistralAPIKey = try await gateway.getSecret(for: .mistralAPIKey) ?? ""
            s3SecretKey = try await gateway.getSecret(for: .s3SecretKey) ?? ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Saves settings and secrets to persistent storage.
    @discardableResult
    public func save() async -> Bool {
        do {
            try await gateway.saveSettings(settings)

            if mistralAPIKey.isEmpty {
                try await gateway.removeSecret(for: .mistralAPIKey)
            } else {
                try await gateway.setSecret(mistralAPIKey, for: .mistralAPIKey)
            }

            if s3SecretKey.isEmpty {
                try await gateway.removeSecret(for: .s3SecretKey)
            } else {
                try await gateway.setSecret(s3SecretKey, for: .s3SecretKey)
            }

            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Tests S3 connectivity by sending a HEAD request to the bucket.
    public func testS3() async {
        s3TestResult = .testing
        do {
            guard !settings.s3EndpointURL.isEmpty,
                  !settings.s3AccessKey.isEmpty,
                  !settings.s3BucketName.isEmpty,
                  !s3SecretKey.isEmpty else {
                s3TestResult = .failure("Fill in all S3 fields first")
                return
            }
            try await connectivityUseCase.testS3(
                settings: settings,
                s3SecretKey: s3SecretKey
            )
            s3TestResult = .success
        } catch {
            s3TestResult = .failure(error.localizedDescription)
        }
    }

    /// Tests Mistral API connectivity by listing available models.
    public func testMistral() async {
        mistralTestResult = .testing
        do {
            guard !mistralAPIKey.isEmpty else {
                mistralTestResult = .failure("Enter an API key first")
                return
            }
            try await connectivityUseCase.testMistral(apiKey: mistralAPIKey)
            mistralTestResult = .success
        } catch {
            mistralTestResult = .failure(error.localizedDescription)
        }
    }
}
