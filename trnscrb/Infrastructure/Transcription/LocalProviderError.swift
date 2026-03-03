import Foundation

/// Errors raised by local Apple transcription/OCR providers.
public enum LocalProviderError: Error, Sendable, Equatable {
    /// Local providers can only process local file URLs.
    case localFileRequired
    /// Local mode is not available on this macOS version.
    case localModeUnavailable
    /// The input file could not be read.
    case unreadableInput(String)
    /// No text was recognized from the input.
    case noRecognizedContent
    /// Speech recognition permission is not granted.
    case speechAuthorizationDenied
    /// Speech recognition failed.
    case transcriptionFailed(String)
    /// OCR failed.
    case ocrFailed(String)
}

extension LocalProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .localFileRequired:
            return "Local provider requires a local file URL."
        case .localModeUnavailable:
            return "Local Apple mode requires macOS 26 or newer."
        case .unreadableInput(let details):
            return details
        case .noRecognizedContent:
            return "No recognizable content found."
        case .speechAuthorizationDenied:
            return "Speech recognition permission was denied."
        case .transcriptionFailed(let details):
            return details
        case .ocrFailed(let details):
            return details
        }
    }
}
