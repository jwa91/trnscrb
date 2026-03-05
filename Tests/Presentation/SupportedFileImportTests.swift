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
