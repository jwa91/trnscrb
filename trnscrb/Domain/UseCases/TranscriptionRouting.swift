import Foundation

/// Errors raised while resolving a provider route for a file.
public enum TranscriptionRoutingError: Error, Sendable, Equatable {
    /// No provider matches the resolved mode and file extension.
    case providerUnavailable(fileType: FileType, mode: ProviderMode)
}

extension TranscriptionRoutingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .providerUnavailable(let fileType, let mode):
            return "No provider available for \(String(describing: fileType)) in \(mode.rawValue) mode."
        }
    }
}

/// Concrete provider route for a single file processing request.
public struct TranscriptionRoute: Sendable {
    public let transcriber: any TranscriptionGateway
    public let effectiveMode: ProviderMode
}

/// Resolves a provider based on file type, user mode preference, and OS support.
public enum TranscriptionRouting {
    /// Picks a provider route for the dropped file.
    public static func resolve(
        fileType: FileType,
        fileExtension: String,
        settings: AppSettings,
        transcribers: [any TranscriptionGateway],
        isLocalModeAvailable: Bool
    ) throws -> TranscriptionRoute {
        let preferredMode: ProviderMode = settings.mode(for: fileType)
        let effectiveMode: ProviderMode = if preferredMode == .localApple && !isLocalModeAvailable {
            .mistral
        } else {
            preferredMode
        }

        guard let transcriber: (any TranscriptionGateway) = transcribers.first(
            where: { $0.providerMode == effectiveMode && $0.supportedExtensions.contains(fileExtension) }
        ) else {
            throw TranscriptionRoutingError.providerUnavailable(fileType: fileType, mode: effectiveMode)
        }

        return TranscriptionRoute(transcriber: transcriber, effectiveMode: effectiveMode)
    }
}
