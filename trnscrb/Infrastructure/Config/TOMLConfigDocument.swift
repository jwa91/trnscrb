import Foundation

struct TOMLConfigDocument {
    private enum ValueType {
        case string
        case bool
        case int
    }

    private enum ParsedValue {
        case string(String)
        case bool(Bool)
        case int(Int)
    }

    private struct FieldDefinition {
        let fullKey: String
        let key: String
        let valueType: ValueType
    }

    private struct ParsedLine {
        let fullKey: String
        let value: ParsedValue
    }

    private static let canonicalSections: [(section: String, fields: [FieldDefinition])] = [
        (
            section: "storage.s3",
            fields: [
                FieldDefinition(fullKey: "storage.s3.endpoint_url", key: "endpoint_url", valueType: .string),
                FieldDefinition(fullKey: "storage.s3.access_key", key: "access_key", valueType: .string),
                FieldDefinition(fullKey: "storage.s3.bucket_name", key: "bucket_name", valueType: .string),
                FieldDefinition(fullKey: "storage.s3.region", key: "region", valueType: .string),
                FieldDefinition(fullKey: "storage.s3.path_prefix", key: "path_prefix", valueType: .string)
            ]
        ),
        (
            section: "storage.retention",
            fields: [
                FieldDefinition(fullKey: "storage.retention.hours", key: "hours", valueType: .int)
            ]
        ),
        (
            section: "processing.providers",
            fields: [
                FieldDefinition(fullKey: "processing.providers.audio", key: "audio", valueType: .string),
                FieldDefinition(fullKey: "processing.providers.pdf", key: "pdf", valueType: .string),
                FieldDefinition(fullKey: "processing.providers.image", key: "image", valueType: .string)
            ]
        ),
        (
            section: "processing.apple_audio",
            fields: [
                FieldDefinition(
                    fullKey: "processing.apple_audio.locale_identifier",
                    key: "locale_identifier",
                    valueType: .string
                )
            ]
        ),
        (
            section: "output.saving",
            fields: [
                FieldDefinition(fullKey: "output.saving.folder_path", key: "folder_path", valueType: .string)
            ]
        ),
        (
            section: "output.naming",
            fields: [
                FieldDefinition(
                    fullKey: "output.naming.filename_prefix",
                    key: "filename_prefix",
                    valueType: .string
                ),
                FieldDefinition(
                    fullKey: "output.naming.filename_template",
                    key: "filename_template",
                    valueType: .string
                )
            ]
        ),
        (
            section: "general.behavior",
            fields: [
                FieldDefinition(
                    fullKey: "general.behavior.copy_to_clipboard",
                    key: "copy_to_clipboard",
                    valueType: .bool
                )
            ]
        ),
        (
            section: "general.startup",
            fields: [
                FieldDefinition(
                    fullKey: "general.startup.launch_at_login",
                    key: "launch_at_login",
                    valueType: .bool
                )
            ]
        )
    ]

    private static let supportedSectionNames: Set<String> = Set(
        canonicalSections.map(\.section)
    )

    private static let fieldDefinitionsBySection: [String: [String: FieldDefinition]] = {
        var definitions: [String: [String: FieldDefinition]] = [:]
        for section in canonicalSections {
            definitions[section.section] = Dictionary(
                uniqueKeysWithValues: section.fields.map { ($0.key, $0) }
            )
        }
        return definitions
    }()

    private static let fieldDefinitionsByFullKey: [String: FieldDefinition] = {
        Dictionary(
            uniqueKeysWithValues: canonicalSections
                .flatMap(\.fields)
                .map { ($0.fullKey, $0) }
        )
    }()

    private static let legacySchemaErrorMessage: String =
        "Legacy flat config schema is no longer supported. Use sectioned config tables like [storage.s3], [processing.providers], [output.saving], and [general.behavior]."

    private var values: [String: ParsedValue] = [:]

    init(settings: AppSettings) {
        values = [
            "storage.s3.endpoint_url": .string(settings.s3EndpointURL),
            "storage.s3.access_key": .string(settings.s3AccessKey),
            "storage.s3.bucket_name": .string(settings.s3BucketName),
            "storage.s3.region": .string(settings.s3Region),
            "storage.s3.path_prefix": .string(settings.s3PathPrefix),
            "storage.retention.hours": .int(settings.fileRetentionHours),
            "processing.providers.audio": .string(settings.audioProviderMode.rawValue),
            "processing.providers.pdf": .string(settings.pdfProviderMode.rawValue),
            "processing.providers.image": .string(settings.imageProviderMode.rawValue),
            "processing.apple_audio.locale_identifier": .string(settings.appleAudioLocaleIdentifier),
            "output.saving.folder_path": .string(settings.saveFolderPath),
            "output.naming.filename_prefix": .string(settings.outputFileNamePrefix),
            "output.naming.filename_template": .string(settings.outputFileNameTemplate),
            "general.behavior.copy_to_clipboard": .bool(settings.copyToClipboard),
            "general.startup.launch_at_login": .bool(settings.launchAtLogin)
        ]
    }

    init(content: String) throws {
        var currentSection: String?
        var parsedValues: [String: ParsedValue] = [:]

        for (lineNumber, rawLine) in content.components(separatedBy: "\n").enumerated() {
            let line: String = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            if line.hasPrefix("[") {
                currentSection = try Self.parseSection(line, lineNumber: lineNumber + 1)
                continue
            }

            guard let currentSection else {
                if line.contains("=") {
                    throw ConfigError.parseError(Self.legacySchemaErrorMessage)
                }
                throw ConfigError.parseError("Malformed config line \(lineNumber + 1).")
            }

            let parsedLine: ParsedLine = try Self.parseKeyValueLine(
                line,
                lineNumber: lineNumber + 1,
                section: currentSection
            )
            if parsedValues[parsedLine.fullKey] != nil {
                throw ConfigError.parseError(
                    "Duplicate config key '\(parsedLine.fullKey)' on line \(lineNumber + 1)."
                )
            }
            parsedValues[parsedLine.fullKey] = parsedLine.value
        }

        values = parsedValues
    }

    func makeSettings() throws -> AppSettings {
        let defaults: AppSettings = AppSettings()

        let settings: AppSettings = AppSettings(
            s3EndpointURL: stringValue("storage.s3.endpoint_url") ?? defaults.s3EndpointURL,
            s3AccessKey: stringValue("storage.s3.access_key") ?? defaults.s3AccessKey,
            s3BucketName: stringValue("storage.s3.bucket_name") ?? defaults.s3BucketName,
            s3Region: stringValue("storage.s3.region") ?? defaults.s3Region,
            s3PathPrefix: stringValue("storage.s3.path_prefix") ?? defaults.s3PathPrefix,
            saveFolderPath: stringValue("output.saving.folder_path") ?? defaults.saveFolderPath,
            outputFileNamePrefix: stringValue("output.naming.filename_prefix")
                ?? defaults.outputFileNamePrefix,
            outputFileNameTemplate: stringValue("output.naming.filename_template")
                ?? defaults.outputFileNameTemplate,
            copyToClipboard: boolValue("general.behavior.copy_to_clipboard")
                ?? defaults.copyToClipboard,
            fileRetentionHours: intValue("storage.retention.hours") ?? defaults.fileRetentionHours,
            launchAtLogin: boolValue("general.startup.launch_at_login") ?? defaults.launchAtLogin,
            audioProviderMode: try providerModeValue("processing.providers.audio")
                ?? defaults.audioProviderMode,
            appleAudioLocaleIdentifier: stringValue("processing.apple_audio.locale_identifier")
                ?? defaults.appleAudioLocaleIdentifier,
            pdfProviderMode: try providerModeValue("processing.providers.pdf")
                ?? defaults.pdfProviderMode,
            imageProviderMode: try providerModeValue("processing.providers.image")
                ?? defaults.imageProviderMode
        )

        return try settings.validatedForPersistence()
    }

    func serialize() -> String {
        var lines: [String] = [
            "# trnscrb configuration",
            "# Passwords are stored in Keychain and are not written here.",
            ""
        ]

        for (index, section) in Self.canonicalSections.enumerated() {
            lines.append("[\(section.section)]")
            for field in section.fields {
                lines.append("\(field.key) = \(serializedValue(for: field.fullKey))")
            }
            if index < Self.canonicalSections.count - 1 {
                lines.append("")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func stringValue(_ fullKey: String) -> String? {
        guard case .string(let value)? = values[fullKey] else {
            return nil
        }
        return value
    }

    private func boolValue(_ fullKey: String) -> Bool? {
        guard case .bool(let value)? = values[fullKey] else {
            return nil
        }
        return value
    }

    private func intValue(_ fullKey: String) -> Int? {
        guard case .int(let value)? = values[fullKey] else {
            return nil
        }
        return value
    }

    private func providerModeValue(_ fullKey: String) throws -> ProviderMode? {
        guard let rawValue: String = stringValue(fullKey) else {
            return nil
        }
        guard let mode: ProviderMode = ProviderMode(rawValue: rawValue) else {
            throw ConfigError.parseError(
                "Invalid provider mode '\(rawValue)' for '\(fullKey)'. Use 'local' or 'mistral'."
            )
        }
        return mode
    }

    private func serializedValue(for fullKey: String) -> String {
        guard let value: ParsedValue = values[fullKey] else {
            return "\"\""
        }

        switch value {
        case .string(let string):
            return Self.quoted(string)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .int(let int):
            return String(int)
        }
    }

    private static func parseSection(
        _ line: String,
        lineNumber: Int
    ) throws -> String {
        guard line.hasSuffix("]") else {
            throw ConfigError.parseError("Malformed section header on line \(lineNumber).")
        }

        let sectionName: String = String(line.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespaces)
        guard !sectionName.isEmpty else {
            throw ConfigError.parseError("Malformed section header on line \(lineNumber).")
        }
        guard supportedSectionNames.contains(sectionName) else {
            throw ConfigError.parseError(
                "Unknown config section [\(sectionName)] on line \(lineNumber)."
            )
        }
        return sectionName
    }

    private static func parseKeyValueLine(
        _ line: String,
        lineNumber: Int,
        section: String
    ) throws -> ParsedLine {
        guard let separatorIndex = line.firstIndex(of: "=") else {
            throw ConfigError.parseError("Malformed config line \(lineNumber).")
        }

        let key: String = line[..<separatorIndex].trimmingCharacters(in: .whitespaces)
        let rawValue: String = String(line[line.index(after: separatorIndex)...])
            .trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !rawValue.isEmpty else {
            throw ConfigError.parseError("Malformed config line \(lineNumber).")
        }

        guard let definition: FieldDefinition = fieldDefinitionsBySection[section]?[key] else {
            throw ConfigError.parseError(
                "Unknown config key '\(key)' in section [\(section)] on line \(lineNumber)."
            )
        }

        let parsedValue: ParsedValue = try parseValue(
            rawValue,
            as: definition.valueType,
            fullKey: definition.fullKey
        )
        return ParsedLine(fullKey: definition.fullKey, value: parsedValue)
    }

    private static func parseValue(
        _ rawValue: String,
        as type: ValueType,
        fullKey: String
    ) throws -> ParsedValue {
        switch type {
        case .string:
            return .string(try parseQuotedString(rawValue, fullKey: fullKey))
        case .bool:
            switch rawValue {
            case "true":
                return .bool(true)
            case "false":
                return .bool(false)
            default:
                throw ConfigError.parseError(
                    "Invalid boolean '\(rawValue)' for '\(fullKey)'. Use true or false."
                )
            }
        case .int:
            guard let value: Int = Int(rawValue) else {
                throw ConfigError.parseError(
                    "Invalid integer '\(rawValue)' for '\(fullKey)'."
                )
            }
            return .int(value)
        }
    }

    private static func parseQuotedString(
        _ rawValue: String,
        fullKey: String
    ) throws -> String {
        guard rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 else {
            throw ConfigError.parseError(
                "Invalid string for '\(fullKey)'. Use double-quoted TOML strings."
            )
        }

        var result: String = String(rawValue.dropFirst().dropLast())
        result = result
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        return result
    }

    private static func quoted(_ value: String) -> String {
        let escaped: String = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
