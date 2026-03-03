import Foundation
import Testing

@testable import trnscrb

@Suite(.serialized)
struct MistralOCRProviderTests {
    private func makeProvider(
        apiKey: String? = "test-api-key"
    ) -> (MistralOCRProvider, MockRequestHandler) {
        let secrets: [SecretKey: String]
        if let apiKey {
            secrets = [.mistralAPIKey: apiKey]
        } else {
            secrets = [:]
        }
        let gateway: MockSettingsGateway = MockSettingsGateway(secrets: secrets)
        let (_, session, mock) = makeMockURLSession()
        return (MistralOCRProvider(settingsGateway: gateway, urlSession: session), mock)
    }

    // MARK: - Supported extensions

    @Test func supportedExtensionsCoversPDFAndImages() {
        let (provider, _) = makeProvider()
        let expected: Set<String> = FileType.pdfExtensions.union(FileType.imageExtensions)
        #expect(provider.supportedExtensions == expected)
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
