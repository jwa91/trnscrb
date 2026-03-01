import Foundation
import Testing

@testable import trnscrb

/// In-memory mock for SettingsGateway used in ViewModel tests.
final class MockSettingsGateway: SettingsGateway, @unchecked Sendable {
    var settings: AppSettings = AppSettings()
    var secrets: [SecretKey: String] = [:]
    var loadCallCount: Int = 0
    var saveCallCount: Int = 0

    func loadSettings() async throws -> AppSettings {
        loadCallCount += 1
        return settings
    }

    func saveSettings(_ newSettings: AppSettings) async throws {
        saveCallCount += 1
        settings = newSettings
    }

    func getSecret(for key: SecretKey) async throws -> String? {
        secrets[key]
    }

    func setSecret(_ value: String, for key: SecretKey) async throws {
        secrets[key] = value
    }

    func removeSecret(for key: SecretKey) async throws {
        secrets[key] = nil
    }
}

@MainActor
struct SettingsViewModelTests {
    private func makeViewModel(
        settings: AppSettings = AppSettings(),
        secrets: [SecretKey: String] = [:]
    ) -> (SettingsViewModel, MockSettingsGateway) {
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings = settings
        gateway.secrets = secrets
        let vm: SettingsViewModel = SettingsViewModel(gateway: gateway)
        return (vm, gateway)
    }

    // MARK: - Loading

    @Test func loadPopulatesSettingsFromGateway() async {
        let customSettings: AppSettings = AppSettings(
            s3EndpointURL: "https://test.com",
            s3BucketName: "bucket"
        )
        let (vm, _) = makeViewModel(settings: customSettings)
        await vm.load()
        #expect(vm.settings.s3EndpointURL == "https://test.com")
        #expect(vm.settings.s3BucketName == "bucket")
    }

    @Test func loadPopulatesSecretsFromGateway() async {
        let secrets: [SecretKey: String] = [
            .mistralAPIKey: "mk-123",
            .s3SecretKey: "sk-456"
        ]
        let (vm, _) = makeViewModel(secrets: secrets)
        await vm.load()
        #expect(vm.mistralAPIKey == "mk-123")
        #expect(vm.s3SecretKey == "sk-456")
    }

    @Test func loadWithNoSecretsLeavesEmptyStrings() async {
        let (vm, _) = makeViewModel()
        await vm.load()
        #expect(vm.mistralAPIKey == "")
        #expect(vm.s3SecretKey == "")
    }

    // MARK: - Saving

    @Test func savePersistsSettingsToGateway() async {
        let (vm, gateway) = makeViewModel()
        vm.settings.s3EndpointURL = "https://saved.com"
        vm.settings.s3BucketName = "saved-bucket"
        await vm.save()
        #expect(gateway.settings.s3EndpointURL == "https://saved.com")
        #expect(gateway.settings.s3BucketName == "saved-bucket")
    }

    @Test func savePersistsSecretsToKeychain() async {
        let (vm, gateway) = makeViewModel()
        vm.mistralAPIKey = "new-mk"
        vm.s3SecretKey = "new-sk"
        await vm.save()
        #expect(gateway.secrets[.mistralAPIKey] == "new-mk")
        #expect(gateway.secrets[.s3SecretKey] == "new-sk")
    }

    @Test func saveRemovesEmptySecrets() async {
        let secrets: [SecretKey: String] = [
            .mistralAPIKey: "existing",
            .s3SecretKey: "existing"
        ]
        let (vm, gateway) = makeViewModel(secrets: secrets)
        await vm.load()
        vm.mistralAPIKey = ""
        vm.s3SecretKey = ""
        await vm.save()
        #expect(gateway.secrets[.mistralAPIKey] == nil)
        #expect(gateway.secrets[.s3SecretKey] == nil)
    }

    // MARK: - Round-trip

    @Test func loadThenSaveRoundTrip() async {
        let original: AppSettings = AppSettings(
            s3EndpointURL: "https://rt.com",
            copyToClipboard: false,
            fileRetentionHours: 48
        )
        let (vm, gateway) = makeViewModel(
            settings: original,
            secrets: [.mistralAPIKey: "rt-key"]
        )
        await vm.load()
        await vm.save()
        #expect(gateway.settings == original)
        #expect(gateway.secrets[.mistralAPIKey] == "rt-key")
    }
}
