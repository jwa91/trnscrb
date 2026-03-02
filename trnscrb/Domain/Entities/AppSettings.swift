import Foundation

/// Keys for secrets stored in the system keychain.
public enum SecretKey: String, Sendable {
    /// Mistral API key for transcription and OCR.
    case mistralAPIKey = "mistral-api-key"
    /// S3-compatible storage secret key.
    case s3SecretKey = "s3-secret-key"
}

/// Application settings persisted to the config file.
///
/// Secrets (API keys) are NOT part of this struct — they live in Keychain
/// and are accessed through `SettingsGateway` separately.
public struct AppSettings: Sendable, Equatable {
    /// S3-compatible endpoint URL (e.g., "https://nbg1.your-objectstorage.com").
    public var s3EndpointURL: String
    /// S3 access key identifier.
    public var s3AccessKey: String
    /// S3 bucket name.
    public var s3BucketName: String
    /// S3 region (default: "auto").
    public var s3Region: String
    /// Path prefix for uploaded objects (default: "trnscrb/").
    public var s3PathPrefix: String
    /// Folder path where markdown files are saved.
    public var saveFolderPath: String
    /// Whether to also copy markdown output to the clipboard.
    public var copyToClipboard: Bool
    /// Whether to save markdown output to a file in the save folder.
    public var saveToFolder: Bool
    /// Hours to retain files in S3 before cleanup.
    public var fileRetentionHours: Int
    /// Whether to launch at login.
    public var launchAtLogin: Bool

    /// Creates settings with defaults matching SPEC.md.
    public init(
        s3EndpointURL: String = "",
        s3AccessKey: String = "",
        s3BucketName: String = "",
        s3Region: String = "auto",
        s3PathPrefix: String = "trnscrb/",
        saveFolderPath: String = "~/Documents/trnscrb/",
        copyToClipboard: Bool = true,
        saveToFolder: Bool = false,
        fileRetentionHours: Int = 24,
        launchAtLogin: Bool = false
    ) {
        self.s3EndpointURL = s3EndpointURL
        self.s3AccessKey = s3AccessKey
        self.s3BucketName = s3BucketName
        self.s3Region = s3Region
        self.s3PathPrefix = s3PathPrefix
        self.saveFolderPath = saveFolderPath
        self.copyToClipboard = copyToClipboard
        self.saveToFolder = saveToFolder
        self.fileRetentionHours = fileRetentionHours
        self.launchAtLogin = launchAtLogin
    }

    /// Whether the required S3 configuration fields are filled in.
    public var isS3Configured: Bool {
        !s3EndpointURL.isEmpty && !s3AccessKey.isEmpty && !s3BucketName.isEmpty
    }
}
