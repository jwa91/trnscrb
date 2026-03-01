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

    /// Settings gateway for persistence.
    private let gateway: any SettingsGateway

    /// Creates a view model backed by the given settings gateway.
    /// - Parameter gateway: Settings persistence gateway.
    public init(gateway: any SettingsGateway) {
        self.gateway = gateway
    }

    /// Loads settings and secrets from persistent storage.
    public func load() async {
        // Full implementation in Task 4
    }

    /// Saves settings and secrets to persistent storage.
    public func save() async {
        // Full implementation in Task 4
    }
}
