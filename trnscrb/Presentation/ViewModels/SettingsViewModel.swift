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
    /// URL session for connectivity tests.
    private let urlSession: URLSession

    /// Creates a view model backed by the given settings gateway.
    /// - Parameters:
    ///   - gateway: Settings persistence gateway.
    ///   - urlSession: URL session for test requests (injectable for testing).
    public init(gateway: any SettingsGateway, urlSession: URLSession = .shared) {
        self.gateway = gateway
        self.urlSession = urlSession
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
    public func save() async {
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
        } catch {
            self.error = error.localizedDescription
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

            let signer: S3Signer = S3Signer(
                accessKey: settings.s3AccessKey,
                secretKey: s3SecretKey,
                region: settings.s3Region
            )
            guard let bucketURL = URL(
                string: "\(settings.s3EndpointURL)/\(settings.s3BucketName)"
            ) else {
                s3TestResult = .failure("Invalid endpoint URL")
                return
            }

            // ListObjectsV2 with max-keys=0 — lightweight connectivity check
            guard var components = URLComponents(
                url: bucketURL, resolvingAgainstBaseURL: false
            ) else {
                s3TestResult = .failure("Invalid URL components")
                return
            }
            components.queryItems = [
                URLQueryItem(name: "list-type", value: "2"),
                URLQueryItem(name: "max-keys", value: "0")
            ]
            guard let listURL = components.url else {
                s3TestResult = .failure("Could not construct list URL")
                return
            }

            var request: URLRequest = URLRequest(url: listURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            signer.sign(&request, payloadHash: S3Signer.unsignedPayload)

            let (_, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                s3TestResult = .failure("Not an HTTP response")
                return
            }
            if http.statusCode == 200 {
                s3TestResult = .success
            } else {
                s3TestResult = .failure("HTTP \(http.statusCode)")
            }
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

            guard let url = URL(string: "https://api.mistral.ai/v1/models") else {
                mistralTestResult = .failure("Invalid URL")
                return
            }
            var request: URLRequest = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(mistralAPIKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (_, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                mistralTestResult = .failure("Not an HTTP response")
                return
            }
            if http.statusCode == 200 {
                mistralTestResult = .success
            } else if http.statusCode == 401 {
                mistralTestResult = .failure("Invalid API key")
            } else {
                mistralTestResult = .failure("HTTP \(http.statusCode)")
            }
        } catch {
            mistralTestResult = .failure(error.localizedDescription)
        }
    }
}
