import Darwin
import Foundation
import Testing

@testable import trnscrb

struct OutputFolderClientTests {
    private func makeTempPath(_ suffix: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "trnscrb-output-folder-\(suffix)")
    }

    @Test func prepareOutputFolderCreatesMissingDirectory() throws {
        let folderURL: URL = makeTempPath()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let client: OutputFolderClient = OutputFolderClient()

        let preparedURL: URL = try client.prepareOutputFolder(path: folderURL.path())

        #expect(FileManager.default.fileExists(atPath: preparedURL.path()))
    }

    @Test func prepareOutputFolderRejectsExistingFile() throws {
        let fileURL: URL = makeTempPath("file.txt")
        try Data("test".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let client: OutputFolderClient = OutputFolderClient()

        #expect(throws: OutputFolderError.self) {
            try client.prepareOutputFolder(path: fileURL.path())
        }
    }

    @Test func prepareOutputFolderExpandsTilde() throws {
        let homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
        let folderURL: URL = homeURL.appending(path: "trnscrb-output-folder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let client: OutputFolderClient = OutputFolderClient()

        let preparedURL: URL = try client.prepareOutputFolder(
            path: "~/\(folderURL.lastPathComponent)"
        )

        #expect(preparedURL == folderURL)
    }

    @Test func prepareOutputFolderRejectsUnwritableDirectory() throws {
        let folderURL: URL = makeTempPath()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        #expect(chmod(folderURL.path(), 0o555) == 0)
        defer {
            _ = chmod(folderURL.path(), 0o755)
            try? FileManager.default.removeItem(at: folderURL)
        }
        let client: OutputFolderClient = OutputFolderClient()

        #expect(throws: OutputFolderError.self) {
            try client.prepareOutputFolder(path: folderURL.path())
        }
    }

    @Test func bookmarkBase64RoundTripsToPreparedFolder() throws {
        let folderURL: URL = makeTempPath()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let fileAccess: SecurityScopedFileAccessSpy = SecurityScopedFileAccessSpy()
        let client: OutputFolderClient = OutputFolderClient(
            fileAccess: fileAccess,
            requiresSecurityScopedBookmark: false
        )
        let bookmarkBase64: String = try OutputFolderClient.bookmarkBase64(for: folderURL)

        let preparedFolder: PreparedOutputFolder = try client.prepareOutputFolder(
            settings: AppSettings(
                saveFolderPath: "/unused/path",
                saveFolderBookmarkBase64: bookmarkBase64
            )
        )
        preparedFolder.stopAccessing()

        #expect(preparedFolder.url.path() == folderURL.path())
        #expect(preparedFolder.refreshedBookmarkBase64 == nil)
        #expect(fileAccess.recordedStartedURLs() == [folderURL.standardizedFileURL])
        #expect(fileAccess.recordedStoppedURLs() == [folderURL.standardizedFileURL])
    }

    @Test func sandboxedExternalFolderRequiresBookmark() throws {
        let folderURL: URL = makeTempPath()
        let client: OutputFolderClient = OutputFolderClient(
            requiresSecurityScopedBookmark: true
        )

        #expect(throws: OutputFolderError.bookmarkRequired) {
            _ = try client.prepareOutputFolder(
                settings: AppSettings(saveFolderPath: folderURL.path())
            )
        }
    }

    @Test func invalidBookmarkRequestsFolderReselection() throws {
        let client: OutputFolderClient = OutputFolderClient(
            requiresSecurityScopedBookmark: false
        )

        #expect(throws: OutputFolderError.invalidBookmark) {
            _ = try client.prepareOutputFolder(
                settings: AppSettings(
                    saveFolderPath: "/unused/path",
                    saveFolderBookmarkBase64: "not-base64"
                )
            )
        }
    }

    @Test func defaultSaveFolderUsesApplicationSupport() {
        #expect(AppSettings().saveFolderPath == AppSettings.defaultSaveFolderPath)
        #expect(AppSettings.defaultSaveFolderPath == "~/Library/Application Support/trnscrb/Output")
    }
}
