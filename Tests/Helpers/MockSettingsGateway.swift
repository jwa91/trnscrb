import Foundation

@testable import trnscrb

/// In-memory mock for SettingsGateway used across all infrastructure tests.
final class MockSettingsGateway: SettingsGateway, @unchecked Sendable {
    var settings: AppSettings = AppSettings()
    var secrets: [SecretKey: String] = [:]

    func loadSettings() async throws -> AppSettings { settings }
    func saveSettings(_ newSettings: AppSettings) async throws { settings = newSettings }
    func getSecret(for key: SecretKey) async throws -> String? { secrets[key] }
    func setSecret(_ value: String, for key: SecretKey) async throws { secrets[key] = value }
    func removeSecret(for key: SecretKey) async throws { secrets[key] = nil }
}
