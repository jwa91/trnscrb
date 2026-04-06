import Foundation

/// File-system implementation for validating the markdown output folder.
public struct OutputFolderClient: OutputFolderGateway {
    private let fileAccess: any SecurityScopedFileAccessing
    private let requiresSecurityScopedBookmark: Bool

    public init(
        fileAccess: any SecurityScopedFileAccessing = SecurityScopedFileAccess(),
        requiresSecurityScopedBookmark: Bool = Self.isAppSandboxed
    ) {
        self.fileAccess = fileAccess
        self.requiresSecurityScopedBookmark = requiresSecurityScopedBookmark
    }

    public static func bookmarkBase64(for url: URL) throws -> String {
        let data: Data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return data.base64EncodedString()
    }

    public func prepareOutputFolder(path: String) throws -> URL {
        try prepareResolvedOutputFolder(path: path)
    }

    public func prepareOutputFolder(settings: AppSettings) throws -> PreparedOutputFolder {
        let normalizedSettings: AppSettings = settings.normalizedForUse
        if !normalizedSettings.saveFolderBookmarkBase64.isEmpty {
            return try prepareBookmarkedOutputFolder(settings: normalizedSettings)
        }

        let folderURL: URL = resolvedURL(path: normalizedSettings.saveFolderPath)
        if requiresSecurityScopedBookmark, !isInsideAppSupport(folderURL) {
            throw OutputFolderError.bookmarkRequired
        }

        return PreparedOutputFolder(
            url: try prepareResolvedOutputFolder(path: normalizedSettings.saveFolderPath)
        )
    }

    private func prepareBookmarkedOutputFolder(settings: AppSettings) throws -> PreparedOutputFolder {
        guard let bookmarkData: Data = Data(base64Encoded: settings.saveFolderBookmarkBase64) else {
            throw OutputFolderError.invalidBookmark
        }

        var isStale: Bool = false
        let folderURL: URL
        do {
            folderURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL
        } catch {
            throw OutputFolderError.invalidBookmark
        }

        let startedAccessing: Bool = fileAccess.startAccessing(folderURL)
        guard startedAccessing || !requiresSecurityScopedBookmark else {
            throw OutputFolderError.invalidBookmark
        }

        do {
            let preparedURL: URL = try prepareResolvedOutputFolder(path: folderURL.path())
            let refreshedBookmarkBase64: String? = isStale
                ? try Self.bookmarkBase64(for: folderURL)
                : nil
            let stopAccessingHandler: (@Sendable () -> Void)?
            if startedAccessing {
                stopAccessingHandler = { @Sendable in
                    fileAccess.stopAccessing(folderURL)
                }
            } else {
                stopAccessingHandler = nil
            }
            return PreparedOutputFolder(
                url: preparedURL,
                refreshedBookmarkBase64: refreshedBookmarkBase64,
                stopAccessingHandler: stopAccessingHandler
            )
        } catch {
            if startedAccessing {
                fileAccess.stopAccessing(folderURL)
            }
            throw error
        }
    }

    private func prepareResolvedOutputFolder(path: String) throws -> URL {
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

    private func resolvedURL(path: String) -> URL {
        let expandedPath: String = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
            .expandingTildeInPath
        return URL(filePath: expandedPath).standardizedFileURL
    }

    private func isInsideAppSupport(_ folderURL: URL) -> Bool {
        let applicationSupportURL: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support")
        let trnscrbSupportURL: URL = applicationSupportURL
            .appending(path: "trnscrb", directoryHint: .isDirectory)
            .standardizedFileURL
        return folderURL.path() == trnscrbSupportURL.path()
            || folderURL.path().hasPrefix("\(trnscrbSupportURL.path())/")
    }

    public static var isAppSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
