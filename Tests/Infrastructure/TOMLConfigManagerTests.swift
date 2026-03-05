import Foundation
import Testing

@testable import trnscrb

private final class SecretStoreSpy: SecretStore, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var values: [SecretKey: String]
    private var getCounts: [SecretKey: Int] = [:]

    init(values: [SecretKey: String] = [:]) {
        self.values = values
    }

    func get(for key: SecretKey) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        getCounts[key, default: 0] += 1
        return values[key]
    }

    func set(_ value: String, for key: SecretKey) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func remove(for key: SecretKey) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = nil
    }

    func recordedGetCount(for key: SecretKey) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return getCounts[key, default: 0]
    }
}

struct TOMLConfigManagerTests {
    /// Creates a manager backed by a temporary directory, cleaned up automatically.
    private func makeManager() throws -> (TOMLConfigManager, URL) {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        let keychainStore: KeychainStore = KeychainStore(service: "com.trnscrb.test.toml.\(UUID().uuidString)")
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )
        return (manager, tempDir)
    }

    private func cleanupDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Load

    @Test func loadFromNonexistentFileReturnsDefaults() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let settings: AppSettings = try await manager.loadSettings()
        #expect(settings == AppSettings())
    }

    // MARK: - Save and round-trip

    @Test func saveCreatesConfigFile() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        try await manager.saveSettings(AppSettings())
        let filePath: String = tempDir.appending(path: "config.toml").path()
        #expect(FileManager.default.fileExists(atPath: filePath))
    }

    @Test func roundTripPreservesAllFields() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let original: AppSettings = AppSettings(
            s3EndpointURL: "https://nbg1.your-objectstorage.com",
            s3AccessKey: "AKID123",
            s3BucketName: "my-bucket",
            s3Region: "eu-central-1",
            s3PathPrefix: "uploads/",
            saveFolderPath: "~/Desktop/output/",
            outputFileNamePrefix: "notes-",
            outputFileNameTemplate: "{prefix}{fileType}-{timestamp}",
            copyToClipboard: false,
            fileRetentionHours: 48,
            launchAtLogin: true,
            appleAudioLocaleIdentifier: "nl-NL"
        )
        try await manager.saveSettings(original)
        let loaded: AppSettings = try await manager.loadSettings()
        #expect(loaded == original)
    }

    @Test func roundTripWithDefaultValues() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let defaults: AppSettings = AppSettings()
        try await manager.saveSettings(defaults)
        let loaded: AppSettings = try await manager.loadSettings()
        #expect(loaded == defaults)
    }

    @Test func roundTripPreservesProviderModes() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let original: AppSettings = AppSettings(
            audioProviderMode: .localApple,
            pdfProviderMode: .mistral,
            imageProviderMode: .localApple
        )

        try await manager.saveSettings(original)
        let loaded: AppSettings = try await manager.loadSettings()

        #expect(loaded.audioProviderMode == .localApple)
        #expect(loaded.pdfProviderMode == .mistral)
        #expect(loaded.imageProviderMode == .localApple)
    }

    // MARK: - TOML format

    @Test func savedFileIsTOMLFormat() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let settings: AppSettings = AppSettings(
            s3EndpointURL: "https://example.com",
            s3BucketName: "bucket",
            outputFileNamePrefix: "notes-",
            outputFileNameTemplate: "{prefix}{fileType}",
            copyToClipboard: false,
            fileRetentionHours: 12,
            launchAtLogin: true,
            audioProviderMode: .localApple,
            appleAudioLocaleIdentifier: "nl-NL",
            pdfProviderMode: .mistral,
            imageProviderMode: .localApple
        )
        try await manager.saveSettings(settings)
        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = try String(contentsOf: fileURL, encoding: .utf8)
        // Verify key TOML patterns exist
        #expect(content.contains("s3_endpoint_url = \"https://example.com\""))
        #expect(content.contains("s3_bucket_name = \"bucket\""))
        #expect(content.contains("output_file_name_prefix = \"notes-\""))
        #expect(content.contains("output_file_name_template = \"{prefix}{fileType}\""))
        #expect(content.contains("copy_to_clipboard = false"))
        #expect(content.contains("file_retention_hours = 12"))
        #expect(content.contains("launch_at_login = true"))
        #expect(content.contains("audio_provider_mode = \"local\""))
        #expect(content.contains("apple_audio_locale_identifier = \"nl-NL\""))
        #expect(content.contains("pdf_provider_mode = \"mistral\""))
        #expect(content.contains("image_provider_mode = \"local\""))
        #expect(!content.contains("save_to_folder"))
    }

    @Test func saveRewritesSchemaToIncludeProviderModeKeys() async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL: URL = tempDir.appending(path: "config.toml")
        let oldSchema: String = """
        s3_endpoint_url = "https://legacy.example.com"
        s3_access_key = "AKID"
        s3_bucket_name = "bucket"
        """
        try oldSchema.write(to: fileURL, atomically: true, encoding: .utf8)

        let keychainStore: KeychainStore = KeychainStore(service: "com.trnscrb.test.toml.\(UUID().uuidString)")
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )

        let loaded: AppSettings = try await manager.loadSettings()
        try await manager.saveSettings(loaded)

        let rewritten: String = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(rewritten.contains("audio_provider_mode = \"mistral\""))
        #expect(rewritten.contains("pdf_provider_mode = \"mistral\""))
        #expect(rewritten.contains("image_provider_mode = \"mistral\""))
    }

    // MARK: - Edge cases

    @Test func handlesQuotesInStringValues() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let settings: AppSettings = AppSettings(
            s3EndpointURL: "https://example.com/path?a=1&b=\"2\""
        )
        try await manager.saveSettings(settings)
        let loaded: AppSettings = try await manager.loadSettings()
        #expect(loaded.s3EndpointURL == settings.s3EndpointURL)
    }

    @Test func ignoresCommentAndBlankLines() async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        // Write a TOML file with comments and blank lines manually
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = """
        # trnscrb config
        s3_endpoint_url = "https://test.com"

        # S3 settings
        s3_bucket_name = "test-bucket"
        file_retention_hours = 72
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let keychainStore: KeychainStore = KeychainStore(service: "com.trnscrb.test.toml.\(UUID().uuidString)")
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )
        let loaded: AppSettings = try await manager.loadSettings()
        #expect(loaded.s3EndpointURL == "https://test.com")
        #expect(loaded.s3BucketName == "test-bucket")
        #expect(loaded.fileRetentionHours == 72)
        // Fields not in file should be defaults
        #expect(loaded.s3Region == "auto")
        #expect(loaded.copyToClipboard == true)
    }

    @Test func loadIgnoresLegacySaveToFolderLine() async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = """
        save_folder_path = "~/Documents/trnscrb/"
        copy_to_clipboard = true
        save_to_folder = false
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let keychainStore: KeychainStore = KeychainStore(service: "com.trnscrb.test.toml.\(UUID().uuidString)")
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )
        let loaded: AppSettings = try await manager.loadSettings()

        #expect(loaded.saveFolderPath == "~/Documents/trnscrb/")
        #expect(loaded.copyToClipboard == true)
    }

    @Test func loadThrowsParseErrorForMalformedLine() async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = """
        s3_endpoint_url = "https://test.com"
        this is not valid toml
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let keychainStore: KeychainStore = KeychainStore(service: "com.trnscrb.test.toml.\(UUID().uuidString)")
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )

        await #expect(throws: ConfigError.self) {
            _ = try await manager.loadSettings()
        }
    }

    @Test func loadThrowsParseErrorForInvalidBoolean() async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = """
        copy_to_clipboard = maybe
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let keychainStore: KeychainStore = KeychainStore(service: "com.trnscrb.test.toml.\(UUID().uuidString)")
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )

        await #expect(throws: ConfigError.self) {
            _ = try await manager.loadSettings()
        }
    }

    @Test func getSecretUsesCachedValueAfterFirstLookup() async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore: SecretStoreSpy = SecretStoreSpy(
            values: [.mistralAPIKey: "mk-test"]
        )
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            secretStore: secretStore
        )

        let firstValue: String? = try await manager.getSecret(for: .mistralAPIKey)
        let secondValue: String? = try await manager.getSecret(for: .mistralAPIKey)

        #expect(firstValue == "mk-test")
        #expect(secondValue == "mk-test")
        #expect(secretStore.recordedGetCount(for: .mistralAPIKey) == 1)
    }

    @Test func setSecretUpdatesCachedValueWithoutRequeryingStore() async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore: SecretStoreSpy = SecretStoreSpy(
            values: [.mistralAPIKey: "old-value"]
        )
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            secretStore: secretStore
        )

        _ = try await manager.getSecret(for: .mistralAPIKey)
        try await manager.setSecret("new-value", for: .mistralAPIKey)
        let cachedValue: String? = try await manager.getSecret(for: .mistralAPIKey)

        #expect(cachedValue == "new-value")
        #expect(secretStore.recordedGetCount(for: .mistralAPIKey) == 1)
    }

    @Test func removeSecretCachesMissingValueWithoutRequeryingStore() async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore: SecretStoreSpy = SecretStoreSpy(
            values: [.mistralAPIKey: "existing"]
        )
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            secretStore: secretStore
        )

        _ = try await manager.getSecret(for: .mistralAPIKey)
        try await manager.removeSecret(for: .mistralAPIKey)
        let cachedValue: String? = try await manager.getSecret(for: .mistralAPIKey)

        #expect(cachedValue == nil)
        #expect(secretStore.recordedGetCount(for: .mistralAPIKey) == 1)
    }
}
