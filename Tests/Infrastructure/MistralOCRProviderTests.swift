import Foundation
import Testing

@testable import trnscrb

@Suite(.serialized)
struct MistralOCRProviderTests {
    private final class FileAccessSpy: SecurityScopedFileAccessing, @unchecked Sendable {
        private let lock: NSLock = NSLock()
        private var startedURLs: [URL] = []
        private var stoppedURLs: [URL] = []

        func startAccessing(_ url: URL) -> Bool {
            lock.lock()
            startedURLs.append(url)
            lock.unlock()
            return true
        }

        func stopAccessing(_ url: URL) {
            lock.lock()
            stoppedURLs.append(url)
            lock.unlock()
        }

        func recordedStartedURLs() -> [URL] {
            lock.lock()
            defer { lock.unlock() }
            return startedURLs
        }

        func recordedStoppedURLs() -> [URL] {
            lock.lock()
            defer { lock.unlock() }
            return stoppedURLs
        }
    }

    private func makeProvider(
        apiKey: String? = "test-api-key",
        fileAccess: any SecurityScopedFileAccessing = SecurityScopedFileAccess()
    ) -> (MistralOCRProvider, MockRequestHandler) {
        let secrets: [SecretKey: String]
        if let apiKey {
            secrets = [.mistralAPIKey: apiKey]
        } else {
            secrets = [:]
        }
        let gateway: MockSettingsGateway = MockSettingsGateway(secrets: secrets)
        let (_, session, mock) = makeMockURLSession()
        return (
            MistralOCRProvider(
                settingsGateway: gateway,
                urlSession: session,
                fileAccess: fileAccess
            ),
            mock
        )
    }

    // MARK: - PDF request

    @Test func processUsesDocumentURLChunkForPDF() async throws {
        let (provider, mock) = makeProvider()

        mock.handler = { request in
            #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/ocr")
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            #expect(body["model"] as? String == "mistral-ocr-latest")
            let doc = body["document"] as! [String: Any]
            #expect(doc["type"] as? String == "document_url")
            #expect(doc["document_url"] as? String == "https://s3.example.com/bucket/doc.pdf")

            let responseJSON: String = """
            {"pages": [{"index": 0, "markdown": "# Page 1"}, {"index": 1, "markdown": "## Page 2"}]}
            """
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let result: String = try await provider.process(
            sourceURL: URL(string: "https://s3.example.com/bucket/doc.pdf")!
        )
        #expect(result == "# Page 1\n\n## Page 2")
    }

    // MARK: - Image request

    @Test func processUsesImageURLChunkForImages() async throws {
        let (provider, mock) = makeProvider()

        mock.handler = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let doc = body["document"] as! [String: Any]
            #expect(doc["type"] as? String == "image_url")
            #expect(doc["image_url"] as? String == "https://s3.example.com/bucket/photo.jpg")

            let responseJSON: String = """
            {"pages": [{"index": 0, "markdown": "Handwritten notes content"}]}
            """
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let result: String = try await provider.process(
            sourceURL: URL(string: "https://s3.example.com/bucket/photo.jpg")!
        )
        #expect(result == "Handwritten notes content")
    }

    @Test func processUploadsLocalFileThenUsesReturnedFileIDForOCR() async throws {
        let tempDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mistral-ocr-provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileURL: URL = tempDirectory.appendingPathComponent("scan.pdf", isDirectory: false)
        try Data("%PDF-local-test".utf8).write(to: fileURL)

        let fileAccessSpy: FileAccessSpy = FileAccessSpy()
        let (provider, mock) = makeProvider(fileAccess: fileAccessSpy)
        var requestCount: Int = 0

        mock.handler = { request in
            requestCount += 1
            if request.url?.absoluteString == "https://api.mistral.ai/v1/files" {
                let body: String = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
                #expect(body.contains("name=\"purpose\""))
                #expect(body.contains("ocr"))
                #expect(body.contains("name=\"file\"; filename=\"scan.pdf\""))
                #expect(body.contains("Content-Type: application/pdf"))
                let response: HTTPURLResponse = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (response, Data("{\"id\":\"file_123\"}".utf8))
            }

            #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/ocr")
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            #expect(body["model"] as? String == "mistral-ocr-latest")
            let document = body["document"] as! [String: Any]
            #expect(document["file_id"] as? String == "file_123")

            let responseJSON: String = """
            {"pages": [{"index": 0, "markdown": "Local OCR content"}]}
            """
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let result: String = try await provider.process(sourceURL: fileURL)

        #expect(result == "Local OCR content")
        #expect(requestCount == 2)
        #expect(fileAccessSpy.recordedStartedURLs() == [fileURL])
        #expect(fileAccessSpy.recordedStoppedURLs() == [fileURL])
    }

    // MARK: - Error handling

    @Test func processThrowsWhenAPIKeyMissing() async {
        let (provider, _) = makeProvider(apiKey: nil)
        await #expect(throws: MistralError.self) {
            _ = try await provider.process(sourceURL: URL(string: "https://example.com/doc.pdf")!)
        }
    }

    @Test func processThrowsOnNon200Response() async {
        let (provider, mock) = makeProvider()
        mock.handler = { request in
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{\"error\":\"internal\"}".utf8))
        }
        await #expect(throws: MistralError.self) {
            _ = try await provider.process(sourceURL: URL(string: "https://example.com/doc.pdf")!)
        }
    }

    @Test func processThrowsOnMissingPagesField() async {
        let (provider, mock) = makeProvider()
        mock.handler = { request in
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{\"model\":\"ocr\"}".utf8))
        }
        await #expect(throws: MistralError.self) {
            _ = try await provider.process(sourceURL: URL(string: "https://example.com/doc.pdf")!)
        }
    }

    // MARK: - Edge cases

    @Test func processSinglePageOmitsExtraNewlines() async throws {
        let (provider, mock) = makeProvider()
        mock.handler = { request in
            let responseJSON: String = """
            {"pages": [{"index": 0, "markdown": "Single page"}]}
            """
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }
        let result: String = try await provider.process(
            sourceURL: URL(string: "https://example.com/img.png")!
        )
        #expect(result == "Single page")
    }
}
