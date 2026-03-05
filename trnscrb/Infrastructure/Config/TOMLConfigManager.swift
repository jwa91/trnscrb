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
    /// Secret store wrapper for secret storage.
    private let secretStore: any SecretStore
    /// In-memory cache to avoid repeated keychain prompts in the same session.
    private let secretCache: SecretCache = SecretCache()

    /// Creates a config manager.
    /// - Parameters:
    ///   - configDirectory: Override for config directory (defaults to XDG path).
    ///   - keychainStore: Keychain wrapper for secret storage.
    public convenience init(
        configDirectory: URL? = nil,
        keychainStore: KeychainStore = KeychainStore()
    ) {
        self.init(configDirectory: configDirectory, secretStore: keychainStore)
    }

    init(
        configDirectory: URL? = nil,
        secretStore: any SecretStore
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
        self.secretStore = secretStore
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
        return try parse(content)
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
            "output_file_name_prefix = \(quoted(settings.outputFileNamePrefix))",
            "output_file_name_template = \(quoted(settings.outputFileNameTemplate))",
            "copy_to_clipboard = \(settings.copyToClipboard)",
            "file_retention_hours = \(settings.fileRetentionHours)",
            "launch_at_login = \(settings.launchAtLogin)",
            "audio_provider_mode = \(quoted(settings.audioProviderMode.rawValue))",
            "apple_audio_locale_identifier = \(quoted(settings.appleAudioLocaleIdentifier))",
            "pdf_provider_mode = \(quoted(settings.pdfProviderMode.rawValue))",
            "image_provider_mode = \(quoted(settings.imageProviderMode.rawValue))"
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// Parses TOML content into AppSettings, using defaults for missing keys.
    private func parse(_ content: String) throws -> AppSettings {
        var dict: [String: String] = [:]
        for (lineNumber, line) in content.components(separatedBy: "\n").enumerated() {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let eqIndex = trimmed.firstIndex(of: "=") else {
                throw ConfigError.parseError("Malformed config line \(lineNumber + 1)")
            }
            let key: String = trimmed[..<eqIndex].trimmingCharacters(in: .whitespaces)
            let rawValue: String = String(trimmed[trimmed.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !rawValue.isEmpty else {
                throw ConfigError.parseError("Malformed config line \(lineNumber + 1)")
            }
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
            outputFileNamePrefix: dict["output_file_name_prefix"] ?? defaults.outputFileNamePrefix,
            outputFileNameTemplate: dict["output_file_name_template"] ?? defaults.outputFileNameTemplate,
            copyToClipboard: try parseBool(
                dict["copy_to_clipboard"],
                key: "copy_to_clipboard",
                defaultValue: defaults.copyToClipboard
            ),
            fileRetentionHours: try parseInt(
                dict["file_retention_hours"],
                key: "file_retention_hours",
                defaultValue: defaults.fileRetentionHours
            ),
            launchAtLogin: try parseBool(
                dict["launch_at_login"],
                key: "launch_at_login",
                defaultValue: defaults.launchAtLogin
            ),
            audioProviderMode: try parseProviderMode(
                dict["audio_provider_mode"],
                key: "audio_provider_mode",
                defaultValue: defaults.audioProviderMode
            ),
            appleAudioLocaleIdentifier: dict["apple_audio_locale_identifier"]
                ?? defaults.appleAudioLocaleIdentifier,
            pdfProviderMode: try parseProviderMode(
                dict["pdf_provider_mode"],
                key: "pdf_provider_mode",
                defaultValue: defaults.pdfProviderMode
            ),
            imageProviderMode: try parseProviderMode(
                dict["image_provider_mode"],
                key: "image_provider_mode",
                defaultValue: defaults.imageProviderMode
            )
        )
    }

    private func parseBool(_ value: String?, key: String, defaultValue: Bool) throws -> Bool {
        guard let value else { return defaultValue }
        switch value {
        case "true":
            return true
        case "false":
            return false
        default:
            throw ConfigError.parseError("Invalid boolean for \(key)")
        }
    }

    private func parseInt(_ value: String?, key: String, defaultValue: Int) throws -> Int {
        guard let value else { return defaultValue }
        guard let intValue: Int = Int(value) else {
            throw ConfigError.parseError("Invalid integer for \(key)")
        }
        return intValue
    }

    private func parseProviderMode(
        _ value: String?,
        key: String,
        defaultValue: ProviderMode
    ) throws -> ProviderMode {
        guard let value else { return defaultValue }
        guard let mode: ProviderMode = ProviderMode(rawValue: value) else {
            throw ConfigError.parseError("Invalid provider mode for \(key)")
        }
        return mode
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
