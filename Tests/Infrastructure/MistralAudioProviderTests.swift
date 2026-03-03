import Foundation
import Testing

@testable import trnscrb

@Suite(.serialized)
struct MistralAudioProviderTests {
    private func makeProvider(
        apiKey: String? = "test-api-key"
    ) -> (MistralAudioProvider, MockRequestHandler) {
        let secrets: [SecretKey: String]
        if let apiKey {
            secrets = [.mistralAPIKey: apiKey]
        } else {
            secrets = [:]
        }
        let gateway: MockSettingsGateway = MockSettingsGateway(secrets: secrets)
        let (_, session, mock) = makeMockURLSession()
        return (MistralAudioProvider(settingsGateway: gateway, urlSession: session), mock)
    }

    // MARK: - Request format

    @Test func processCallsCorrectEndpoint() async throws {
        let (provider, mock) = makeProvider()

        mock.handler = { request in
            #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/audio/transcriptions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
            #expect(
                request.value(forHTTPHeaderField: "Content-Type")?
                    .hasPrefix("multipart/form-data; boundary=") == true
            )

            let body: String = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
            #expect(body.contains("name=\"model\""))
            #expect(body.contains("voxtral-mini-latest"))
            #expect(body.contains("name=\"file_url\""))
            #expect(body.contains("https://s3.example.com/bucket/file.mp3"))

            let responseJSON: String = """
            {"text": "Hello world", "model": "voxtral-mini-2507"}
            """
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let result: String = try await provider.process(
            sourceURL: URL(string: "https://s3.example.com/bucket/file.mp3")!
        )
        #expect(result == "Hello world")
    }

    // MARK: - Error handling

    @Test func processThrowsWhenAPIKeyMissing() async {
        let (provider, _) = makeProvider(apiKey: nil)
        await #expect(throws: MistralError.self) {
            _ = try await provider.process(sourceURL: URL(string: "https://example.com/f.mp3")!)
        }
    }

    @Test func processThrowsOnNon200Response() async {
        let (provider, mock) = makeProvider()

        mock.handler = { request in
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{\"error\":\"rate limited\"}".utf8))
        }

        await #expect(throws: MistralError.self) {
            _ = try await provider.process(sourceURL: URL(string: "https://example.com/f.mp3")!)
        }
    }

    @Test func processThrowsOnMalformedResponse() async {
        let (provider, mock) = makeProvider()

        mock.handler = { request in
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("not json".utf8))
        }

        await #expect(throws: MistralError.self) {
            _ = try await provider.process(sourceURL: URL(string: "https://example.com/f.mp3")!)
        }
    }
}
