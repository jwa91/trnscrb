import Foundation

/// Errors from file delivery operations.
public enum FileDeliveryError: Error, Sendable {
    /// Could not write the markdown file.
    case writeFailed(String)
}

extension FileDeliveryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .writeFailed(let message):
            return message
        }
    }
}

/// Delivers transcription results by saving markdown as a `.md` file.
///
/// File is saved to the folder configured in `AppSettings.saveFolderPath`.
/// If a file with the same name exists, a timestamp suffix is appended.
public struct FileDelivery: DeliveryGateway {
    /// Gateway for reading the save folder path from settings.
    private let settingsGateway: any SettingsGateway
    /// Validates and resolves the output folder before writing files.
    private let outputFolderGateway: any OutputFolderGateway

    /// Creates a file delivery handler.
    /// - Parameters:
    ///   - settingsGateway: Provides the configured save folder path.
    ///   - outputFolderGateway: Validates and resolves the output folder.
    public init(
        settingsGateway: any SettingsGateway,
        outputFolderGateway: any OutputFolderGateway
    ) {
        self.settingsGateway = settingsGateway
        self.outputFolderGateway = outputFolderGateway
    }

    /// Saves the markdown content as a `.md` file in the configured folder.
    public func deliver(result: TranscriptionResult) async throws -> DeliveryReport {
        var settings: AppSettings = try await settingsGateway.loadSettings().normalizedForUse
        let preparedFolder: PreparedOutputFolder = try outputFolderGateway.prepareOutputFolder(
            settings: settings
        )
        defer {
            preparedFolder.stopAccessing()
        }
        if let refreshedBookmarkBase64: String = preparedFolder.refreshedBookmarkBase64,
           refreshedBookmarkBase64 != settings.saveFolderBookmarkBase64 {
            settings.saveFolderBookmarkBase64 = refreshedBookmarkBase64
            try await settingsGateway.saveSettings(settings)
        }
        let folderURL: URL = preparedFolder.url
        AppLog.delivery.info("Saving markdown for \(result.sourceFileName, privacy: .public) to \(folderURL.path(), privacy: .public)")

        let fileName: String = OutputFileNameFormatter.fileName(
            sourceFileName: result.sourceFileName,
            fileType: result.sourceFileType,
            settings: settings.normalizedForUse
        )
        let fileURL: URL = outputFileURL(folder: folderURL, fileName: fileName)

        try result.markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        AppLog.delivery.info("Saved markdown to \(fileURL.path(), privacy: .public)")
        return DeliveryReport(savedFileURL: fileURL)
    }

    /// Determines the output file URL, appending a timestamp if the file already exists.
    private func outputFileURL(folder: URL, fileName: String) -> URL {
        let primary: URL = folder.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: primary.path()) else {
            return primary
        }
        let baseName: String = (fileName as NSString).deletingPathExtension
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let timestamp: String = formatter.string(from: Date())

        var attempt: Int = 0
        while true {
            let suffix: String = attempt == 0 ? timestamp : "\(timestamp)-\(attempt)"
            let candidate: URL = folder.appending(path: "\(baseName)-\(suffix).md")
            if !FileManager.default.fileExists(atPath: candidate.path()) {
                return candidate
            }
            attempt += 1
        }
    }
}
