import Foundation
import Speech

enum SettingsValidationError: Error, Sendable {
    case negativeFileRetentionHours(Int)
    case unsupportedAppleAudioLocaleIdentifier(String)
}

extension SettingsValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .negativeFileRetentionHours(let value):
            return "File retention hours must be 0 or greater. Received \(value)."
        case .unsupportedAppleAudioLocaleIdentifier(let identifier):
            return "Apple audio locale '\(identifier)' is not supported on this Mac."
        }
    }
}

extension AppSettings {
    var normalizedForUse: AppSettings {
        AppSettings(
            s3EndpointURL: s3EndpointURL.normalizedEndpointURLString,
            s3AccessKey: s3AccessKey.trimmedCredentialValue,
            s3BucketName: s3BucketName.trimmedCredentialValue,
            s3Region: s3Region.trimmedCredentialValue,
            s3PathPrefix: s3PathPrefix.trimmedPathPrefix,
            saveFolderPath: saveFolderPath.trimmingCharacters(in: .whitespacesAndNewlines),
            outputFileNamePrefix: outputFileNamePrefix.trimmingCharacters(in: .whitespacesAndNewlines),
            outputFileNameTemplate: outputFileNameTemplate.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            copyToClipboard: copyToClipboard,
            fileRetentionHours: fileRetentionHours,
            launchAtLogin: launchAtLogin,
            audioProviderMode: audioProviderMode,
            appleAudioLocaleIdentifier: normalizedAppleAudioLocaleIdentifier,
            pdfProviderMode: pdfProviderMode,
            imageProviderMode: imageProviderMode
        )
    }

    func validatedForPersistence() throws -> AppSettings {
        let normalized: AppSettings = normalizedForUse
        guard normalized.fileRetentionHours >= 0 else {
            throw SettingsValidationError.negativeFileRetentionHours(
                normalized.fileRetentionHours
            )
        }
        guard normalized.normalizedAppleAudioLocaleIdentifier.isSupportedAppleSpeechLocale else {
            throw SettingsValidationError.unsupportedAppleAudioLocaleIdentifier(
                normalized.normalizedAppleAudioLocaleIdentifier
            )
        }
        return normalized
    }

    var normalizedAppleAudioLocaleIdentifier: String {
        let trimmed: String = appleAudioLocaleIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return AppSettings.defaultAppleAudioLocaleIdentifier
        }
        return trimmed
    }
}

extension String {
    var trimmedCredentialValue: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedEndpointURLString: String {
        let trimmed: String = trimmedCredentialValue
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    var trimmedPathPrefix: String {
        let trimmed: String = trimmedCredentialValue
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasSuffix("/") {
            return trimmed
        }
        return "\(trimmed)/"
    }

    var isSupportedAppleSpeechLocale: Bool {
        SFSpeechRecognizer.supportedLocales().contains { $0.identifier == self }
    }
}
