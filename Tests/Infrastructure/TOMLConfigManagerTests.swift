import Foundation
import Speech
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
    private func makeManager() throws -> (TOMLConfigManager, URL) {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        let keychainStore: KeychainStore = KeychainStore(
            service: "com.janwillemaltink.trnscrb.test.toml.\(UUID().uuidString)"
        )
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )
        return (manager, tempDir)
    }

    private func cleanupDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func supportedLocaleIdentifier() -> String {
        SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted().first
            ?? AppSettings.defaultAppleAudioLocaleIdentifier
    }

    @Test func loadFromNonexistentFileReturnsDefaults() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }

        let settings: AppSettings = try await manager.loadSettings()
        let expected: AppSettings = try AppSettings().validatedForPersistence()

        #expect(settings == expected)
    }

    @Test func saveCreatesConfigFile() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }

        try await manager.saveSettings(
            AppSettings(appleAudioLocaleIdentifier: supportedLocaleIdentifier())
        )

        let filePath: String = tempDir.appending(path: "config.toml").path()
        #expect(FileManager.default.fileExists(atPath: filePath))
    }

    @Test func roundTripPreservesAllFieldsAcrossFlatSchema() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }

        let original: AppSettings = AppSettings(
            s3EndpointURL: "nbg1.your-objectstorage.com",
            s3AccessKey: "AKID123",
            s3BucketName: "my-bucket",
            s3Region: "eu-central-1",
            s3PathPrefix: "uploads",
            saveFolderPath: " ~/Desktop/output/ ",
            outputFileNamePrefix: " notes- ",
            outputFileNameTemplate: " {prefix}{fileType}-{timestamp} ",
            copyToClipboard: false,
            fileRetentionHours: 48,
            launchAtLogin: true,
            audioProviderMode: .mistral,
            appleAudioLocaleIdentifier: " \(supportedLocaleIdentifier()) ",
            pdfProviderMode: .localApple,
            imageProviderMode: .mistral
        )

        try await manager.saveSettings(original)
        let loaded: AppSettings = try await manager.loadSettings()
        let expected: AppSettings = try original.validatedForPersistence()

        #expect(loaded == expected)
    }

    @Test func savedFileUsesCanonicalFlatSchemaAndOrder() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }

        let settings: AppSettings = AppSettings(
            s3EndpointURL: "s3.example.com",
            s3AccessKey: "AKID",
            s3BucketName: "bucket",
            s3Region: "auto",
            s3PathPrefix: "uploads",
            saveFolderPath: "~/Documents/trnscrb/",
            outputFileNamePrefix: "notes-",
            outputFileNameTemplate: "{prefix}{fileType}",
            copyToClipboard: false,
            fileRetentionHours: 12,
            launchAtLogin: true,
            audioProviderMode: .localApple,
            appleAudioLocaleIdentifier: supportedLocaleIdentifier(),
            pdfProviderMode: .mistral,
            imageProviderMode: .localApple
        )

        try await manager.saveSettings(settings)
        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = try String(contentsOf: fileURL, encoding: .utf8)

        let expected: String = """
        # trnscrb configuration
        # Passwords are stored in Keychain and are not written here.

        pipeline.mirroring.enabled = false

        storage.s3.endpoint_url = "https://s3.example.com"
        storage.s3.access_key = "AKID"
        storage.s3.bucket_name = "bucket"
        storage.s3.region = "auto"
        storage.s3.path_prefix = "uploads/"
        storage.retention.hours = 12

        processing.providers.audio = "local"
        processing.providers.pdf = "mistral"
        processing.providers.image = "local"
        processing.apple_audio.locale_identifier = "\(supportedLocaleIdentifier())"

        output.saving.folder_path = "~/Documents/trnscrb/"
        output.naming.filename_prefix = "notes-"
        output.naming.filename_template = "{prefix}{fileType}"

        general.behavior.copy_to_clipboard = false
        general.startup.launch_at_login = true
        """

        #expect(content == expected + "\n")
        #expect(!content.contains("mistral_api_key"))
        #expect(!content.contains("s3_secret_key"))
        #expect(!content.contains("[storage.s3]"))
    }

    @Test func loadParsesFlatSchemaRegardlessOfKeyOrder() async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = """
        # trnscrb config

        general.startup.launch_at_login = false
        output.naming.filename_template = "{prefix}{originalFilename}"
        storage.s3.path_prefix = "archive/"
        processing.providers.image = "local"
        storage.s3.bucket_name = "test-bucket"
        processing.apple_audio.locale_identifier = " \(supportedLocaleIdentifier()) "
        storage.retention.hours = 72
        output.naming.filename_prefix = "notes-"
        storage.s3.region = "auto"
        output.saving.folder_path = "~/Documents/trnscrb/"
        processing.providers.pdf = "local"
        general.behavior.copy_to_clipboard = true
        storage.s3.access_key = "AKID"
        processing.providers.audio = "mistral"
        storage.s3.endpoint_url = "https://test.com"
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let keychainStore: KeychainStore = KeychainStore(
            service: "com.janwillemaltink.trnscrb.test.toml.\(UUID().uuidString)"
        )
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )

        let loaded: AppSettings = try await manager.loadSettings()

        #expect(loaded.s3EndpointURL == "https://test.com")
        #expect(loaded.s3AccessKey == "AKID")
        #expect(loaded.s3BucketName == "test-bucket")
        #expect(loaded.s3PathPrefix == "archive/")
        #expect(loaded.fileRetentionHours == 72)
        #expect(loaded.audioProviderMode == .mistral)
        #expect(loaded.appleAudioLocaleIdentifier == supportedLocaleIdentifier())
        #expect(loaded.outputFileNameTemplate == "{prefix}{originalFilename}")
        #expect(loaded.copyToClipboard == true)
        #expect(loaded.launchAtLogin == false)
    }

    @Test func roundTripPreservesBucketMirroringEnabled() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }

        let original: AppSettings = AppSettings(
            bucketMirroringEnabled: true,
            appleAudioLocaleIdentifier: supportedLocaleIdentifier()
        )
        try await manager.saveSettings(original)
        let loaded: AppSettings = try await manager.loadSettings()

        #expect(loaded.bucketMirroringEnabled == true)
    }

    @Test func missingBucketMirroringKeyDefaultsToFalse() async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = """
        storage.s3.endpoint_url = "https://test.com"
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let keychainStore: KeychainStore = KeychainStore(
            service: "com.janwillemaltink.trnscrb.test.toml.\(UUID().uuidString)"
        )
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )

        let loaded: AppSettings = try await manager.loadSettings()
        #expect(loaded.bucketMirroringEnabled == false)
    }

    @Test func savedFileIncludesBucketMirroringKey() async throws {
        let (manager, tempDir) = try makeManager()
        defer { cleanupDir(tempDir) }

        let settings: AppSettings = AppSettings(
            bucketMirroringEnabled: true,
            appleAudioLocaleIdentifier: supportedLocaleIdentifier()
        )
        try await manager.saveSettings(settings)

        let fileURL: URL = tempDir.appending(path: "config.toml")
        let content: String = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("pipeline.mirroring.enabled = true"))
    }

    @Test func loadRejectsSectionHeaders() async throws {
        try await assertLoadFails(
            """
            [storage.s3]
            endpoint_url = "https://legacy.example.com"
            """,
            messageFragment: "Section headers are not supported"
        )
    }

    @Test func loadRejectsUnknownKey() async throws {
        try await assertLoadFails(
            """
            storage.s3.endpoint_url = "https://test.com"
            storage.s3.unknown_key = "nope"
            """,
            messageFragment: "Unknown config key 'storage.s3.unknown_key'"
        )
    }

    @Test func loadRejectsInvalidProviderMode() async throws {
        try await assertLoadFails(
            """
            processing.providers.audio = "cloud"
            processing.providers.pdf = "local"
            processing.providers.image = "local"
            """,
            messageFragment: "Invalid provider mode 'cloud'"
        )
    }

    @Test func loadRejectsNegativeRetentionHours() async throws {
        try await assertLoadFails(
            """
            storage.retention.hours = -1
            """,
            messageFragment: "0 or greater"
        )
    }

    @Test func loadRejectsUnsupportedAppleAudioLocaleIdentifier() async throws {
        try await assertLoadFails(
            """
            processing.apple_audio.locale_identifier = "xx-INVALID"
            """,
            messageFragment: "not supported on this Mac"
        )
    }

    @Test func loadRejectsUnquotedStringValues() async throws {
        try await assertLoadFails(
            """
            storage.s3.endpoint_url = https://test.com
            """,
            messageFragment: "Use double-quoted TOML strings"
        )
    }

    @Test func loadRejectsMalformedLine() async throws {
        try await assertLoadFails(
            """
            this is not valid toml
            """,
            messageFragment: "Malformed config line"
        )
    }

    @Test func loadRejectsDuplicateKey() async throws {
        try await assertLoadFails(
            """
            storage.s3.endpoint_url = "https://test.com"
            storage.s3.endpoint_url = "https://test-2.com"
            """,
            messageFragment: "Duplicate config key 'storage.s3.endpoint_url'"
        )
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

    private func assertLoadFails(
        _ content: String,
        messageFragment: String
    ) async throws {
        let tempDir: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL: URL = tempDir.appending(path: "config.toml")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let keychainStore: KeychainStore = KeychainStore(
            service: "com.trnscrb.test.toml.\(UUID().uuidString)"
        )
        let manager: TOMLConfigManager = TOMLConfigManager(
            configDirectory: tempDir,
            keychainStore: keychainStore
        )

        do {
            _ = try await manager.loadSettings()
            Issue.record("Expected config load to fail")
        } catch {
            #expect(error.localizedDescription.contains(messageFragment))
        }
    }
}
