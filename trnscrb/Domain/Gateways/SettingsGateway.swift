import Foundation

/// Abstracts reading and writing application settings.
///
/// Config-file settings and keychain secrets are both accessed
/// through this single gateway — the domain doesn't know where
/// each value is stored.
public protocol SettingsGateway: Sendable {
    /// Loads application settings from persistent storage.
    func loadSettings() async throws -> AppSettings

    /// Saves application settings to persistent storage.
    func saveSettings(_ settings: AppSettings) async throws

    /// Retrieves a secret from secure storage.
    /// - Parameter key: Which secret to retrieve.
    /// - Returns: The secret value, or `nil` if not set.
    func getSecret(for key: SecretKey) async throws -> String?

    /// Stores a secret in secure storage.
    /// - Parameters:
    ///   - value: The secret value to store.
    ///   - key: Which secret to store.
    func setSecret(_ value: String, for key: SecretKey) async throws

    /// Removes a secret from secure storage.
    /// - Parameter key: Which secret to remove.
    func removeSecret(for key: SecretKey) async throws
}
