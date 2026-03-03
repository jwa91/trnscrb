import Foundation

/// File-system implementation for validating the markdown output folder.
public struct OutputFolderClient: OutputFolderGateway {
    public init() {}

    public func prepareOutputFolder(path: String) throws -> URL {
        let fileManager: FileManager = .default
        let trimmedPath: String = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw OutputFolderError.missingPath
        }

        let expandedPath: String = (trimmedPath as NSString).expandingTildeInPath
        let folderURL: URL = URL(filePath: expandedPath)
        let resolvedURL: URL = folderURL.standardizedFileURL

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: resolvedURL.path(), isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw OutputFolderError.notDirectory
            }
        } else {
            do {
                try fileManager.createDirectory(at: resolvedURL, withIntermediateDirectories: true)
            } catch {
                throw OutputFolderError.notWritable
            }
        }

        let probeURL: URL = resolvedURL.appending(path: ".trnscrb-write-test-\(UUID().uuidString)")
        do {
            try Data().write(to: probeURL, options: .atomic)
            try fileManager.removeItem(at: probeURL)
        } catch {
            try? fileManager.removeItem(at: probeURL)
            throw OutputFolderError.notWritable
        }

        return resolvedURL
    }
}
