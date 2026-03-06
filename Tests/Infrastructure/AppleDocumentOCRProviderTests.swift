import Foundation
import Testing

@testable import trnscrb

struct AppleDocumentOCRProviderTests {
    @Test func processRequiresLocalFileURL() async {
        let provider: AppleDocumentOCRProvider = AppleDocumentOCRProvider()
        let remoteURL: URL = URL(string: "https://example.com/doc.pdf")!

        do {
            _ = try await provider.process(sourceURL: remoteURL)
            Issue.record("Expected local file validation error")
        } catch let error as LocalProviderError {
            #expect(error == .localFileRequired)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func processRejectsUnsupportedLocalExtension() async {
        let provider: AppleDocumentOCRProvider = AppleDocumentOCRProvider()

        do {
            _ = try await provider.process(sourceURL: URL(filePath: "/tmp/doc.txt"))
            Issue.record("Expected unsupported local input error")
        } catch let error as LocalProviderError {
            #expect(error == .unreadableInput("Unsupported local document extension: .txt"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
