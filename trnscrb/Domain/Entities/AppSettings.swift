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
    /// Default template used when generating markdown filenames.
    public static let defaultFileNameTemplate: String = "{originalFilename}"
    /// Default speech locale used by Apple's on-device audio transcription.
    public static let defaultAppleAudioLocaleIdentifier: String = "en-US"

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
    /// Optional prefix injected by the output filename template.
    public var outputFileNamePrefix: String
    /// Template used to generate saved markdown filenames.
    public var outputFileNameTemplate: String
    /// Whether to also copy markdown output to the clipboard.
    public var copyToClipboard: Bool
    /// Hours to retain files in S3 before cleanup.
    public var fileRetentionHours: Int
    /// Whether to launch at login.
    public var launchAtLogin: Bool
    /// Provider mode used for audio files.
    public var audioProviderMode: ProviderMode
    /// Speech locale identifier used for local Apple audio transcription.
    public var appleAudioLocaleIdentifier: String
    /// Provider mode used for PDF files.
    public var pdfProviderMode: ProviderMode
    /// Provider mode used for image files.
    public var imageProviderMode: ProviderMode

    /// Creates settings with defaults matching SPEC.md.
    public init(
        s3EndpointURL: String = "",
        s3AccessKey: String = "",
        s3BucketName: String = "",
        s3Region: String = "auto",
        s3PathPrefix: String = "trnscrb/",
        saveFolderPath: String = "~/Documents/trnscrb/",
        outputFileNamePrefix: String = "",
        outputFileNameTemplate: String = AppSettings.defaultFileNameTemplate,
        copyToClipboard: Bool = true,
        fileRetentionHours: Int = 24,
        launchAtLogin: Bool = false,
        audioProviderMode: ProviderMode = .localApple,
        appleAudioLocaleIdentifier: String = AppSettings.defaultAppleAudioLocaleIdentifier,
        pdfProviderMode: ProviderMode = .localApple,
        imageProviderMode: ProviderMode = .localApple
    ) {
        self.s3EndpointURL = s3EndpointURL
        self.s3AccessKey = s3AccessKey
        self.s3BucketName = s3BucketName
        self.s3Region = s3Region
        self.s3PathPrefix = s3PathPrefix
        self.saveFolderPath = saveFolderPath
        self.outputFileNamePrefix = outputFileNamePrefix
        self.outputFileNameTemplate = outputFileNameTemplate
        self.copyToClipboard = copyToClipboard
        self.fileRetentionHours = fileRetentionHours
        self.launchAtLogin = launchAtLogin
        self.audioProviderMode = audioProviderMode
        self.appleAudioLocaleIdentifier = appleAudioLocaleIdentifier
        self.pdfProviderMode = pdfProviderMode
        self.imageProviderMode = imageProviderMode
    }

    /// Whether the required S3 configuration fields are filled in.
    public var isS3Configured: Bool {
        !s3EndpointURL.isEmpty && !s3AccessKey.isEmpty && !s3BucketName.isEmpty
    }

    /// Returns the configured provider mode for the given file type.
    public func mode(for fileType: FileType) -> ProviderMode {
        switch fileType {
        case .audio:
            return audioProviderMode
        case .pdf:
            return pdfProviderMode
        case .image:
            return imageProviderMode
        }
    }

    /// Whether any media type is configured to use the cloud provider.
    public var requiresCloudCredentials: Bool {
        audioProviderMode == .mistral
            || pdfProviderMode == .mistral
            || imageProviderMode == .mistral
    }
}
