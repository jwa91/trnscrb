import Foundation
import Testing

@testable import trnscrb

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
            copyToClipboard: false,
            fileRetentionHours: 48,
            launchAtLogin: true
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

    // MARK: - TOML format

    @Test func savedFileIsTOMLFormat() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }
        let settings: AppSettings = AppSettings(
            s3EndpointURL: "https://example.com",
            s3BucketName: "bucket",
            copyToClipboard: false,
            fileRetentionHours: 12,
            launchAtLogin: true
        )
        try await manager.saveSettings(settings)
        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = try String(contentsOf: fileURL, encoding: .utf8)
        // Verify key TOML patterns exist
        #expect(content.contains("s3_endpoint_url = \"https://example.com\""))
        #expect(content.contains("s3_bucket_name = \"bucket\""))
        #expect(content.contains("copy_to_clipboard = false"))
        #expect(content.contains("file_retention_hours = 12"))
        #expect(content.contains("launch_at_login = true"))
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
}
