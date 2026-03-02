import Foundation

/// Errors from config file operations.
public enum ConfigError: Error, Sendable {
    /// The config file content could not be parsed.
    case parseError(String)
}

/// Reads and writes application settings to a TOML config file.
///
/// Config path follows XDG: `$XDG_CONFIG_HOME/trnscrb/config.toml`,
/// defaulting to `~/.config/trnscrb/config.toml`.
/// Secrets are delegated to the injected `KeychainStore`.
public final class TOMLConfigManager: SettingsGateway, @unchecked Sendable {
    /// Directory containing `config.toml`.
    private let configDirectory: URL
    /// Keychain wrapper for secret storage.
    private let keychainStore: KeychainStore

    /// Creates a config manager.
    /// - Parameters:
    ///   - configDirectory: Override for config directory (defaults to XDG path).
    ///   - keychainStore: Keychain wrapper for secret storage.
    public init(
        configDirectory: URL? = nil,
        keychainStore: KeychainStore = KeychainStore()
    ) {
        if let configDirectory {
            self.configDirectory = configDirectory
        } else {
            if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
                self.configDirectory = URL(filePath: xdg).appending(path: "trnscrb")
            } else {
                self.configDirectory = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: ".config/trnscrb")
            }
        }
        self.keychainStore = keychainStore
    }

    /// URL of the TOML config file.
    private var configFileURL: URL {
        configDirectory.appending(path: "config.toml")
    }

    // MARK: - SettingsGateway conformance

    /// Loads settings from the TOML config file. Returns defaults if file doesn't exist.
    public func loadSettings() async throws -> AppSettings {
        let path: String = configFileURL.path()
        guard FileManager.default.fileExists(atPath: path) else {
            return AppSettings()
        }
        let content: String = try String(contentsOf: configFileURL, encoding: .utf8)
        return parse(content)
    }

    /// Saves settings to the TOML config file, creating the directory if needed.
    public func saveSettings(_ settings: AppSettings) async throws {
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true
        )
        let content: String = serialize(settings)
        try content.write(to: configFileURL, atomically: true, encoding: .utf8)
    }

    /// Retrieves a secret from the Keychain.
    public func getSecret(for key: SecretKey) async throws -> String? {
        try keychainStore.get(for: key)
    }

    /// Stores a secret in the Keychain.
    public func setSecret(_ value: String, for key: SecretKey) async throws {
        try keychainStore.set(value, for: key)
    }

    /// Removes a secret from the Keychain.
    public func removeSecret(for key: SecretKey) async throws {
        try keychainStore.remove(for: key)
    }

    // MARK: - TOML serialization

    /// Serializes settings to TOML format.
    private func serialize(_ settings: AppSettings) -> String {
        let lines: [String] = [
            "s3_endpoint_url = \(quoted(settings.s3EndpointURL))",
            "s3_access_key = \(quoted(settings.s3AccessKey))",
            "s3_bucket_name = \(quoted(settings.s3BucketName))",
            "s3_region = \(quoted(settings.s3Region))",
            "s3_path_prefix = \(quoted(settings.s3PathPrefix))",
            "save_folder_path = \(quoted(settings.saveFolderPath))",
            "copy_to_clipboard = \(settings.copyToClipboard)",
            "save_to_folder = \(settings.saveToFolder)",
            "file_retention_hours = \(settings.fileRetentionHours)",
            "launch_at_login = \(settings.launchAtLogin)"
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parses TOML content into AppSettings, using defaults for missing keys.
    private func parse(_ content: String) -> AppSettings {
        var dict: [String: String] = [:]
        for line in content.components(separatedBy: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key: String = trimmed[..<eqIndex].trimmingCharacters(in: .whitespaces)
            let rawValue: String = String(trimmed[trimmed.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespaces)
            dict[key] = unquote(rawValue)
        }

        let defaults: AppSettings = AppSettings()
        return AppSettings(
            s3EndpointURL: dict["s3_endpoint_url"] ?? defaults.s3EndpointURL,
            s3AccessKey: dict["s3_access_key"] ?? defaults.s3AccessKey,
            s3BucketName: dict["s3_bucket_name"] ?? defaults.s3BucketName,
            s3Region: dict["s3_region"] ?? defaults.s3Region,
            s3PathPrefix: dict["s3_path_prefix"] ?? defaults.s3PathPrefix,
            saveFolderPath: dict["save_folder_path"] ?? defaults.saveFolderPath,
            copyToClipboard: dict["copy_to_clipboard"].map { $0 == "true" } ?? defaults.copyToClipboard,
            saveToFolder: dict["save_to_folder"].map { $0 == "true" } ?? defaults.saveToFolder,
            fileRetentionHours: Int(dict["file_retention_hours"] ?? "") ?? defaults.fileRetentionHours,
            launchAtLogin: dict["launch_at_login"].map { $0 == "true" } ?? defaults.launchAtLogin
        )
    }

    /// Wraps a string value in TOML double quotes, escaping inner quotes and backslashes.
    private func quoted(_ value: String) -> String {
        let escaped: String = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Strips surrounding double quotes and unescapes a TOML string value.
    private func unquote(_ value: String) -> String {
        var result: String = value
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count >= 2 {
            result = String(result.dropFirst().dropLast())
            result = result
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return result
    }
}
