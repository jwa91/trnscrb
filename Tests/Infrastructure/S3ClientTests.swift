import Foundation
import Testing

@testable import trnscrb

@Suite(.serialized)
struct S3ClientTests {
    private func makeClient(
        endpoint: String = "https://s3.example.com",
        accessKey: String = "AKID",
        secretKey: String = "SECRET",
        bucket: String = "test-bucket",
        region: String = "us-east-1",
        pathPrefix: String = "trnscrb/"
    ) -> (S3Client, MockRequestHandler) {
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings = AppSettings(
            s3EndpointURL: endpoint,
            s3AccessKey: accessKey,
            s3BucketName: bucket,
            s3Region: region,
            s3PathPrefix: pathPrefix
        )
        gateway.secrets[.s3SecretKey] = secretKey
        let (session, mock) = makeMockURLSession()
        let client: S3Client = S3Client(settingsGateway: gateway, urlSession: session)
        return (client, mock)
    }

    // MARK: - Upload

    @Test func uploadSendsPUTRequest() async throws {
        let (client, mock) = makeClient()
        let tempFile: URL = FileManager.default.temporaryDirectory.appending(path: "test.mp3")
        try Data("audio-content".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        mock.handler = { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path.contains("test-bucket/trnscrb/test-key.mp3") == true)
            #expect(request.value(forHTTPHeaderField: "Authorization")?.contains("AWS4-HMAC-SHA256") == true)
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let presignedURL: URL = try await client.upload(fileURL: tempFile, key: "trnscrb/test-key.mp3")
        #expect(presignedURL.absoluteString.contains("X-Amz-Signature"))
    }

    @Test func uploadThrowsWhenS3SecretMissing() async throws {
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings = AppSettings(s3EndpointURL: "https://s3.example.com", s3AccessKey: "AK", s3BucketName: "b")
        // No secret key set
        let (session, _) = makeMockURLSession()
        let client: S3Client = S3Client(settingsGateway: gateway, urlSession: session)
        let tempFile: URL = FileManager.default.temporaryDirectory.appending(path: "test.mp3")
        try Data("x".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        await #expect(throws: S3Error.self) {
            _ = try await client.upload(fileURL: tempFile, key: "k")
        }
    }

    // MARK: - Delete

    @Test func deleteSendsDELETERequest() async throws {
        let (client, mock) = makeClient()

        mock.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path.contains("test-bucket/trnscrb/file.mp3") == true)
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        try await client.delete(key: "trnscrb/file.mp3")
    }

    // MARK: - List

    @Test func listCreatedBeforeParsesXMLResponse() async throws {
        let (client, mock) = makeClient()
        let xmlResponse: String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult>
            <Contents>
                <Key>trnscrb/old-file.mp3</Key>
                <LastModified>2026-02-01T00:00:00.000Z</LastModified>
            </Contents>
            <Contents>
                <Key>trnscrb/new-file.mp3</Key>
                <LastModified>2026-03-01T00:00:00.000Z</LastModified>
            </Contents>
        </ListBucketResult>
        """

        mock.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString.contains("list-type=2") == true)
            let response: HTTPURLResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(xmlResponse.utf8))
        }

        // Cutoff: 2026-02-15 — only old-file should be returned
        var cutoffComponents: DateComponents = DateComponents()
        cutoffComponents.year = 2026
        cutoffComponents.month = 2
        cutoffComponents.day = 15
        cutoffComponents.timeZone = TimeZone(identifier: "UTC")
        let cutoff: Date = Calendar(identifier: .gregorian).date(from: cutoffComponents)!

        let keys: [String] = try await client.listCreatedBefore(cutoff)
        #expect(keys == ["trnscrb/old-file.mp3"])
    }

    @Test func listCreatedBeforeReturnsEmptyForNoMatches() async throws {
        let (client, mock) = makeClient()
        let xmlResponse: String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult></ListBucketResult>
        """

        mock.handler = { _ in
            let response: HTTPURLResponse = HTTPURLResponse(
                url: URL(string: "https://s3.example.com")!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data(xmlResponse.utf8))
        }

        let keys: [String] = try await client.listCreatedBefore(Date())
        #expect(keys.isEmpty)
    }
}
