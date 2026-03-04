import Foundation

@testable import trnscrb

/// In-memory mock for SettingsGateway used across all infrastructure tests.
actor MockSettingsGateway: SettingsGateway {
    private var settings: AppSettings
    private var secrets: [SecretKey: String]
    private var loadSettingsCallCount: Int = 0

    init(
        settings: AppSettings = AppSettings(),
        secrets: [SecretKey: String] = [:]
    ) {
        self.settings = settings
        self.secrets = secrets
    }

    func setSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    func snapshotSettings() -> AppSettings {
        settings
    }

    func setSecrets(_ secrets: [SecretKey: String]) {
        self.secrets = secrets
    }

    func snapshotSecrets() -> [SecretKey: String] {
        secrets
    }

    func recordedLoadSettingsCallCount() -> Int {
        loadSettingsCallCount
    }

    func loadSettings() async throws -> AppSettings {
        loadSettingsCallCount += 1
        return settings
    }
    func saveSettings(_ newSettings: AppSettings) async throws { settings = newSettings }
    func getSecret(for key: SecretKey) async throws -> String? { secrets[key] }
    func setSecret(_ value: String, for key: SecretKey) async throws { secrets[key] = value }
    func removeSecret(for key: SecretKey) async throws { secrets[key] = nil }
}
