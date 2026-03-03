import Foundation
import Testing

@testable import trnscrb

struct AppleDocumentOCRProviderTests {
    @Test func metadataMatchesExpectedRouting() {
        let provider: AppleDocumentOCRProvider = AppleDocumentOCRProvider()

        #expect(provider.providerMode == .localApple)
        #expect(provider.sourceKind == .localFile)
        #expect(provider.supportedExtensions == FileType.pdfExtensions.union(FileType.imageExtensions))
    }

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

    @Test func processThrowsUnavailableErrorOnPreMacOS26() async {
        if #available(macOS 26, *) {
            return
        }

        let provider: AppleDocumentOCRProvider = AppleDocumentOCRProvider()
        do {
            _ = try await provider.process(sourceURL: URL(filePath: "/tmp/doc.pdf"))
            Issue.record("Expected unavailable error")
        } catch let error as LocalProviderError {
            #expect(error == .localModeUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
