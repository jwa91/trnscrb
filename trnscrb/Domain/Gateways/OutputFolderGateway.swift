import Foundation

/// Errors raised while validating or preparing the output folder.
public enum OutputFolderError: Error, Sendable, Equatable {
    case missingPath
    case notDirectory
    case notWritable
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
        }
    }
}

/// Validates and prepares the folder used for markdown output.
public protocol OutputFolderGateway: Sendable {
    /// Resolves and prepares the output folder for use.
    /// - Parameter path: User-configured folder path.
    /// - Returns: An absolute resolved folder URL ready for file writes.
    func prepareOutputFolder(path: String) throws -> URL
}
