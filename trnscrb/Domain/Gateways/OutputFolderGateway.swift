import Foundation

/// Errors raised while validating or preparing the output folder.
public enum OutputFolderError: Error, Sendable, Equatable {
    case missingPath
    case notDirectory
    case notWritable
    case invalidBookmark
    case bookmarkRequired
}

extension OutputFolderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingPath:
            return "Choose a save folder in settings."
        case .notDirectory:
            return "Save folder must be a folder, not a file."
        case .notWritable:
            return "Save folder isn't writable. Choose another folder in settings."
        case .invalidBookmark:
            return "Save folder access expired. Choose the save folder again in settings."
        case .bookmarkRequired:
            return "Choose the save folder again in settings so trnscrb can keep access after restart."
        }
    }
}

/// Prepared output folder plus any security-scoped access that must stay open
/// while callers read/write inside the folder.
public struct PreparedOutputFolder: @unchecked Sendable {
    public let url: URL
    public let refreshedBookmarkBase64: String?
    private let stopAccessingHandler: (@Sendable () -> Void)?

    public init(
        url: URL,
        refreshedBookmarkBase64: String? = nil,
        stopAccessingHandler: (@Sendable () -> Void)? = nil
    ) {
        self.url = url
        self.refreshedBookmarkBase64 = refreshedBookmarkBase64
        self.stopAccessingHandler = stopAccessingHandler
    }

    public func stopAccessing() {
        stopAccessingHandler?()
    }
}

/// Validates and prepares the folder used for markdown output.
public protocol OutputFolderGateway: Sendable {
    /// Resolves and prepares the output folder for use.
    /// - Parameter path: User-configured folder path.
    /// - Returns: An absolute resolved folder URL ready for file writes.
    func prepareOutputFolder(path: String) throws -> URL

    /// Resolves and prepares the output folder from full app settings.
    /// Implementations can use a stored security-scoped bookmark when needed.
    func prepareOutputFolder(settings: AppSettings) throws -> PreparedOutputFolder
}

public extension OutputFolderGateway {
    func prepareOutputFolder(settings: AppSettings) throws -> PreparedOutputFolder {
        PreparedOutputFolder(url: try prepareOutputFolder(path: settings.saveFolderPath))
    }
}
