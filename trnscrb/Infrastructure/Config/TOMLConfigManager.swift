import Foundation

/// Errors from config file operations.
public enum ConfigError: Error, Sendable {
    /// The config file content could not be parsed.
    case parseError(String)
}

extension ConfigError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .parseError(let message):
            return message
        }
    }
}

/// Reads and writes application settings to a TOML config file.
///
/// Config path lives in Application Support so sandboxed builds write inside
/// their container. A legacy XDG config is migrated once if present.
/// Secrets are delegated to the injected `KeychainStore`.
public final class TOMLConfigManager: SettingsGateway, @unchecked Sendable {
    static var defaultConfigDirectoryURL: URL {
        let applicationSupportURL: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support")
        return applicationSupportURL.appending(path: "trnscrb")
    }

    static var legacyConfigDirectoryURL: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            return URL(filePath: xdg).appending(path: "trnscrb")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/trnscrb")
    }

    static var defaultConfigFileURL: URL {
        defaultConfigDirectoryURL.appending(path: "config.toml")
    }

    /// Directory containing `config.toml`.
    private let configDirectory: URL
    /// Legacy XDG config directory used for one-time migration.
    private let legacyConfigDirectory: URL?
    /// Secret store wrapper for secret storage.
    private let secretStore: any SecretStore
    /// In-memory cache to avoid repeated keychain prompts in the same session.
    private let secretCache: SecretCache = SecretCache()

    /// Creates a config manager.
    /// - Parameters:
    ///   - configDirectory: Override for config directory (defaults to Application Support).
    ///   - keychainStore: Keychain wrapper for secret storage.
    public convenience init(
        configDirectory: URL? = nil,
        legacyConfigDirectory: URL? = nil,
        keychainStore: KeychainStore = KeychainStore()
    ) {
        self.init(
            configDirectory: configDirectory,
            legacyConfigDirectory: legacyConfigDirectory,
            secretStore: keychainStore
        )
    }

    init(
        configDirectory: URL? = nil,
        legacyConfigDirectory: URL? = nil,
        secretStore: any SecretStore
    ) {
        if let configDirectory {
            self.configDirectory = configDirectory
        } else {
            self.configDirectory = Self.defaultConfigDirectoryURL
        }
        self.legacyConfigDirectory = legacyConfigDirectory
            ?? (configDirectory == nil ? Self.legacyConfigDirectoryURL : nil)
        self.secretStore = secretStore
    }

    /// URL of the TOML config file.
    private var configFileURL: URL {
        configDirectory.appending(path: "config.toml")
    }

    private var legacyConfigFileURL: URL? {
        legacyConfigDirectory?.appending(path: "config.toml")
    }

    // MARK: - SettingsGateway conformance

    /// Loads settings from the TOML config file. Returns defaults if file doesn't exist.
    public func loadSettings() async throws -> AppSettings {
        let path: String = configFileURL.path()
        guard FileManager.default.fileExists(atPath: path) else {
            if let migratedSettings: AppSettings = try migrateLegacySettingsIfNeeded() {
                return migratedSettings
            }
            return try AppSettings().validatedForPersistence()
        }
        let content: String = try String(contentsOf: configFileURL, encoding: .utf8)
        let document: TOMLConfigDocument = try TOMLConfigDocument(content: content)
        return try document.makeSettings()
    }

    /// Saves settings to the TOML config file, creating the directory if needed.
    public func saveSettings(_ settings: AppSettings) async throws {
        try writeSettings(settings)
    }

    private func writeSettings(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true
        )
        let normalizedSettings: AppSettings = try settings.validatedForPersistence()
        let content: String = TOMLConfigDocument(settings: normalizedSettings).serialize()
        try content.write(to: configFileURL, atomically: true, encoding: .utf8)
    }

    /// Retrieves a secret from the Keychain.
    public func getSecret(for key: SecretKey) async throws -> String? {
        let cachedSecret: SecretCache.LookupResult = secretCache.cachedSecret(for: key)
        switch cachedSecret {
        case .cached(let value):
            return value
        case .notLoaded:
            break
        }

        let value: String? = try secretStore.get(for: key)
        secretCache.store(value, for: key)
        return value
    }

    /// Stores a secret in the Keychain.
    public func setSecret(_ value: String, for key: SecretKey) async throws {
        try secretStore.set(value, for: key)
        secretCache.store(value, for: key)
    }

    /// Removes a secret from the Keychain.
    public func removeSecret(for key: SecretKey) async throws {
        try secretStore.remove(for: key)
        secretCache.store(nil, for: key)
    }

    private func migrateLegacySettingsIfNeeded() throws -> AppSettings? {
        guard let legacyConfigFileURL,
              legacyConfigFileURL.standardizedFileURL != configFileURL.standardizedFileURL,
              FileManager.default.fileExists(atPath: legacyConfigFileURL.path()) else {
            return nil
        }

        let content: String = try String(contentsOf: legacyConfigFileURL, encoding: .utf8)
        let document: TOMLConfigDocument = try TOMLConfigDocument(content: content)
        var settings: AppSettings = try document.makeSettings()
        settings.saveFolderBookmarkBase64 = ""
        try writeSettings(settings)
        return settings
    }

}

private final class SecretCache: @unchecked Sendable {
    enum LookupResult {
        case notLoaded
        case cached(String?)
    }

    private enum Entry {
        case value(String)
        case missing
    }

    private let lock: NSLock = NSLock()
    private var values: [SecretKey: Entry] = [:]

    func cachedSecret(for key: SecretKey) -> LookupResult {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = values[key] else {
            return .notLoaded
        }

        switch entry {
        case .value(let value):
            return .cached(value)
        case .missing:
            return .cached(nil)
        }
    }

    func store(_ value: String?, for key: SecretKey) {
        lock.lock()
        values[key] = value.map(Entry.value) ?? .missing
        lock.unlock()
    }
}
