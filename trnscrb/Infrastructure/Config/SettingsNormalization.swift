import Foundation

extension AppSettings {
    var normalizedForUse: AppSettings {
        AppSettings(
            s3EndpointURL: s3EndpointURL.normalizedEndpointURLString,
            s3AccessKey: s3AccessKey.trimmedCredentialValue,
            s3BucketName: s3BucketName.trimmedCredentialValue,
            s3Region: s3Region.trimmedCredentialValue,
            s3PathPrefix: s3PathPrefix.trimmedPathPrefix,
            saveFolderPath: saveFolderPath.trimmingCharacters(in: .whitespacesAndNewlines),
            copyToClipboard: copyToClipboard,
            fileRetentionHours: fileRetentionHours,
            launchAtLogin: launchAtLogin,
            audioProviderMode: audioProviderMode,
            pdfProviderMode: pdfProviderMode,
            imageProviderMode: imageProviderMode
        )
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
}
