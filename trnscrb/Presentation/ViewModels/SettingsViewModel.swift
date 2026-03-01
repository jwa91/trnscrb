import Foundation

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

    /// Settings gateway for persistence.
    private let gateway: any SettingsGateway

    /// Creates a view model backed by the given settings gateway.
    /// - Parameter gateway: Settings persistence gateway.
    public init(gateway: any SettingsGateway) {
        self.gateway = gateway
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
}
