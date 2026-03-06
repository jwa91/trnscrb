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
    /// Controls whether the Mistral API key is visible in the UI.
    @Published public var isMistralAPIKeyVisible: Bool = false
    /// Controls whether the S3 secret key is visible in the UI.
    @Published public var isS3SecretKeyVisible: Bool = false

    /// Settings gateway for persistence.
    private let gateway: any SettingsGateway
    /// Domain use case for connectivity testing.
    private let connectivityUseCase: TestConnectivityUseCase
    /// Validates and resolves the output folder before settings are saved.
    private let outputFolderGateway: any OutputFolderGateway
    /// Persists settings, secrets, and launch-at-login atomically.
    private let saveSettingsUseCase: SaveSettingsUseCase
    /// Creates a view model backed by the given settings gateway.
    /// - Parameters:
    ///   - gateway: Settings persistence gateway.
    ///   - connectivityUseCase: Connectivity test use case.
    ///   - saveSettingsUseCase: Saves settings, secrets, and launch-at-login changes.
    public init(
        gateway: any SettingsGateway,
        connectivityUseCase: TestConnectivityUseCase,
        outputFolderGateway: any OutputFolderGateway,
        saveSettingsUseCase: SaveSettingsUseCase
    ) {
        self.gateway = gateway
        self.connectivityUseCase = connectivityUseCase
        self.outputFolderGateway = outputFolderGateway
        self.saveSettingsUseCase = saveSettingsUseCase
    }

    /// Loads settings and secrets from persistent storage.
    public func load() async {
        do {
            let loadedSettings: AppSettings = try await gateway.loadSettings()
            settings = loadedSettings
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
            settings = settings.normalizedForUse
            mistralAPIKey = mistralAPIKey.trimmedCredentialValue
            s3SecretKey = s3SecretKey.trimmedCredentialValue
            _ = try outputFolderGateway.prepareOutputFolder(path: settings.saveFolderPath)

            try await saveSettingsUseCase.save(
                settings: settings,
                mistralAPIKey: mistralAPIKey,
                s3SecretKey: s3SecretKey
            )

            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    public var resolvedSaveFolderPath: String {
        let trimmedPath: String = settings.saveFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "" }
        return URL(filePath: (trimmedPath as NSString).expandingTildeInPath).standardizedFileURL.path()
    }

    public var outputFileNamePreview: String {
        OutputFileNameFormatter.fileName(
            sourceFileName: "meeting-note.m4a",
            fileType: .audio,
            settings: settings.normalizedForUse
        )
    }

    /// Tests S3 connectivity by sending a HEAD request to the bucket.
    public func testS3() async {
        s3TestResult = .testing
        do {
            settings = settings.normalizedForUse
            s3SecretKey = s3SecretKey.trimmedCredentialValue

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
            mistralAPIKey = mistralAPIKey.trimmedCredentialValue
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
