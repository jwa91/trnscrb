import Foundation
import Testing

@testable import trnscrb

@Suite(.serialized)
struct MistralAudioProviderTests {
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
    ) -> (MistralAudioProvider, MockRequestHandler) {
        let secrets: [SecretKey: String]
        if let apiKey {
            secrets = [.mistralAPIKey: apiKey]
        } else {
            secrets = [:]
        }
        let gateway: MockSettingsGateway = MockSettingsGateway(secrets: secrets)
        let (_, session, mock) = makeMockURLSession()
        return (
            MistralAudioProvider(
                settingsGateway: gateway,
                urlSession: session,
                fileAccess: fileAccess
            ),
            mock
        )
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

    @Test func processUploadsLocalAudioFileUsingMultipartFileField() async throws {
        let tempDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mistral-audio-provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let fileURL: URL = tempDirectory.appendingPathComponent("sample.mp3", isDirectory: false)
        try Data("local audio".utf8).write(to: fileURL)

        let fileAccessSpy: FileAccessSpy = FileAccessSpy()
        let (provider, mock) = makeProvider(fileAccess: fileAccessSpy)

        mock.handler = { request in
            let body: String = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
            #expect(body.contains("name=\"model\""))
            #expect(body.contains("voxtral-mini-latest"))
            #expect(body.contains("name=\"file\"; filename=\"sample.mp3\""))
            #expect(body.contains("Content-Type: audio/mpeg"))
            #expect(!body.contains("name=\"file_url\""))

            let responseJSON: String = """
            {"text": "Uploaded local audio"}
            """
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let result: String = try await provider.process(sourceURL: fileURL)

        #expect(result == "Uploaded local audio")
        #expect(fileAccessSpy.recordedStartedURLs() == [fileURL])
        #expect(fileAccessSpy.recordedStoppedURLs() == [fileURL])
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
