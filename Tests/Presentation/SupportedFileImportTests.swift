import AppKit
import Foundation
import Testing

@testable import trnscrb

@Suite(.serialized)
@MainActor
struct SupportedFileImportTests {
    @Test func loadFileURLsExtractsFileURLsFromProviders() async {
        let firstURL: URL = URL(filePath: "/tmp/meeting.mp3")
        let secondURL: URL = URL(filePath: "/tmp/scan.pdf")
        let providers: [NSItemProvider] = [
            NSItemProvider(object: firstURL as NSURL),
            NSItemProvider(object: secondURL as NSURL),
            NSItemProvider(object: "not-a-file" as NSString)
        ]

        let urls: [URL] = await withCheckedContinuation { continuation in
            SupportedFileImport.loadFileURLs(from: providers) { loadedURLs in
                continuation.resume(returning: loadedURLs)
            }
        }

        #expect(Set(urls) == Set([firstURL, secondURL]))
    }

    @Test func loadFileURLsMaterializesProviderBackedFilesIntoStableTempCopies() async throws {
        let fileManager: FileManager = .default
        let tempDirectory: URL = fileManager.temporaryDirectory
            .appendingPathComponent("supported-file-import-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let sourceURL: URL = tempDirectory.appendingPathComponent("scan.jpeg", isDirectory: false)
        let sourceData: Data = Data([0x01, 0x02, 0x03, 0x04])
        try sourceData.write(to: sourceURL)

        let provider: NSItemProvider = try #require(NSItemProvider(contentsOf: sourceURL))
        let urls: [URL] = await withCheckedContinuation { continuation in
            SupportedFileImport.loadFileURLs(from: [provider]) { loadedURLs in
                continuation.resume(returning: loadedURLs)
            }
        }

        let materializedURL: URL = try #require(urls.first)
        #expect(materializedURL != sourceURL)
        #expect(materializedURL.lastPathComponent == sourceURL.lastPathComponent)
        #expect(materializedURL.path().contains("/trnscrb-imports/"))
        #expect(try Data(contentsOf: materializedURL) == sourceData)
    }

    @Test func containsSupportedFileDetectsSupportedExtensionsInMixedBatch() {
        let urls: [URL] = [
            URL(filePath: "/tmp/notes.txt"),
            URL(filePath: "/tmp/recording.mp3")
        ]

        #expect(SupportedFileImport.containsSupportedFile(urls))
    }

    @Test func containsSupportedFileReturnsFalseWhenNoSupportedFilesExist() {
        let urls: [URL] = [
            URL(filePath: "/tmp/notes.txt"),
            URL(filePath: "/tmp/archive.zip")
        ]

        #expect(!SupportedFileImport.containsSupportedFile(urls))
    }
}
