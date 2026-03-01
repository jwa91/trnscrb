import Foundation

/// Errors from file delivery operations.
public enum FileDeliveryError: Error, Sendable {
    /// Could not write the markdown file.
    case writeFailed(String)
}

/// Delivers transcription results by saving markdown as a `.md` file.
///
/// File is saved to the folder configured in `AppSettings.saveFolderPath`.
/// If a file with the same name exists, a timestamp suffix is appended.
public struct FileDelivery: DeliveryGateway {
    /// Gateway for reading the save folder path from settings.
    private let settingsGateway: any SettingsGateway

    /// Creates a file delivery handler.
    /// - Parameter settingsGateway: Provides the configured save folder path.
    public init(settingsGateway: any SettingsGateway) {
        self.settingsGateway = settingsGateway
    }

    /// Saves the markdown content as a `.md` file in the configured folder.
    public func deliver(result: TranscriptionResult) async throws {
        let settings: AppSettings = try await settingsGateway.loadSettings()
        let folderPath: String = (settings.saveFolderPath as NSString).expandingTildeInPath
        let folderURL: URL = URL(filePath: folderPath)

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let baseName: String = (result.sourceFileName as NSString).deletingPathExtension
        let fileURL: URL = outputFileURL(folder: folderURL, baseName: baseName)

        try result.markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Determines the output file URL, appending a timestamp if the file already exists.
    private func outputFileURL(folder: URL, baseName: String) -> URL {
        let primary: URL = folder.appending(path: "\(baseName).md")
        guard FileManager.default.fileExists(atPath: primary.path()) else {
            return primary
        }
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let timestamp: String = formatter.string(from: Date())
        return folder.appending(path: "\(baseName)-\(timestamp).md")
    }
}
