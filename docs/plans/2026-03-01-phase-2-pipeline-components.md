# Phase 2 — Pipeline Components

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement all infrastructure components — S3 storage client, clipboard/file delivery, and Mistral API providers for audio transcription and OCR — so Phase 3 can wire them into the end-to-end pipeline.

**Architecture:** Each component implements a domain gateway protocol. S3Client implements StorageGateway using AWS Signature V4 signing (hand-rolled with CryptoKit). ClipboardDelivery and FileDelivery implement DeliveryGateway. MistralAudioProvider and MistralOCRProvider implement TranscriptionGateway. All components fetch credentials from SettingsGateway at call time so settings changes take effect immediately. No external dependencies.

**Tech Stack:** Foundation (URLSession, XMLParser, FileManager), CryptoKit (HMAC-SHA256 for AWS Sig V4), AppKit (NSPasteboard for clipboard)

**API Reference:**
- Mistral Audio: `POST https://api.mistral.ai/v1/audio/transcriptions` — JSON body with `model` + `file_url`, response has `text` field
- Mistral OCR: `POST https://api.mistral.ai/v1/ocr` — JSON body with `model` + `document` (DocumentURLChunk or ImageURLChunk), response has `pages[].markdown`

---

## Task 1: Shared Test Helpers + S3Signer (TDD)

**Files:**
- Create: `Tests/Helpers/MockURLProtocol.swift`
- Create: `Tests/Helpers/MockSettingsGateway.swift`
- Create: `trnscrb/Infrastructure/Storage/S3Signer.swift`
- Create: `Tests/Infrastructure/S3SignerTests.swift`

**Context:** S3Signer is a pure struct that implements AWS Signature V4 signing. It uses CryptoKit (built into macOS) for HMAC-SHA256. Two public methods: `sign()` adds Authorization header to a URLRequest, `presignedURL()` generates a time-limited GET URL. Test helpers are shared across all Phase 2 tests.

### Step 1: Create shared test helpers

Create `Tests/Helpers/MockURLProtocol.swift`:

```swift
import Foundation

/// Intercepts URLSession requests for testing. Set `requestHandler` before each test.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// Handler that receives the request and returns a response + data.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("MockURLProtocol.requestHandler not set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Creates a URLSession that routes all requests through MockURLProtocol.
func makeMockURLSession() -> URLSession {
    let config: URLSessionConfiguration = .ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}
```

Create `Tests/Helpers/MockSettingsGateway.swift`:

```swift
import Foundation

@testable import trnscrb

/// In-memory mock for SettingsGateway used across all infrastructure tests.
final class MockSettingsGateway: SettingsGateway, @unchecked Sendable {
    var settings: AppSettings = AppSettings()
    var secrets: [SecretKey: String] = [:]

    func loadSettings() async throws -> AppSettings { settings }
    func saveSettings(_ newSettings: AppSettings) async throws { settings = newSettings }
    func getSecret(for key: SecretKey) async throws -> String? { secrets[key] }
    func setSecret(_ value: String, for key: SecretKey) async throws { secrets[key] = value }
    func removeSecret(for key: SecretKey) async throws { secrets[key] = nil }
}
```

### Step 2: Write S3Signer tests

Create `Tests/Infrastructure/S3SignerTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

struct S3SignerTests {
    private let signer: S3Signer = S3Signer(
        accessKey: "AKIDEXAMPLE",
        secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        region: "us-east-1"
    )

    // Fixed date: 2026-03-01T12:00:00Z
    private var fixedDate: Date {
        var components: DateComponents = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - sign()

    @Test func signAddsAuthorizationHeader() {
        var request: URLRequest = URLRequest(
            url: URL(string: "https://s3.us-east-1.amazonaws.com/my-bucket/test-key")!
        )
        request.httpMethod = "PUT"
        signer.sign(&request, date: fixedDate, payloadHash: S3Signer.unsignedPayload)

        let auth: String? = request.value(forHTTPHeaderField: "Authorization")
        #expect(auth != nil)
        #expect(auth!.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260301/us-east-1/s3/aws4_request"))
        #expect(auth!.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"))
        #expect(auth!.contains("Signature="))
    }

    @Test func signAddsDateAndPayloadHeaders() {
        var request: URLRequest = URLRequest(
            url: URL(string: "https://s3.us-east-1.amazonaws.com/my-bucket/test-key")!
        )
        request.httpMethod = "PUT"
        signer.sign(&request, date: fixedDate, payloadHash: S3Signer.unsignedPayload)

        #expect(request.value(forHTTPHeaderField: "x-amz-date") == "20260301T120000Z")
        #expect(request.value(forHTTPHeaderField: "x-amz-content-sha256") == S3Signer.unsignedPayload)
    }

    @Test func signIsDeterministic() {
        var req1: URLRequest = URLRequest(url: URL(string: "https://s3.example.com/bucket/key")!)
        req1.httpMethod = "GET"
        signer.sign(&req1, date: fixedDate, payloadHash: S3Signer.unsignedPayload)

        var req2: URLRequest = URLRequest(url: URL(string: "https://s3.example.com/bucket/key")!)
        req2.httpMethod = "GET"
        signer.sign(&req2, date: fixedDate, payloadHash: S3Signer.unsignedPayload)

        #expect(req1.value(forHTTPHeaderField: "Authorization") == req2.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - presignedURL()

    @Test func presignedURLContainsAllRequiredParameters() {
        let baseURL: URL = URL(string: "https://s3.example.com/bucket/trnscrb/file.mp3")!
        let presigned: URL = signer.presignedURL(for: baseURL, expiration: 3600, date: fixedDate)
        let components: URLComponents = URLComponents(url: presigned, resolvingAgainstBaseURL: false)!
        let paramNames: Set<String> = Set(components.queryItems?.map(\.name) ?? [])

        #expect(paramNames.contains("X-Amz-Algorithm"))
        #expect(paramNames.contains("X-Amz-Credential"))
        #expect(paramNames.contains("X-Amz-Date"))
        #expect(paramNames.contains("X-Amz-Expires"))
        #expect(paramNames.contains("X-Amz-SignedHeaders"))
        #expect(paramNames.contains("X-Amz-Signature"))
    }

    @Test func presignedURLPreservesOriginalPath() {
        let baseURL: URL = URL(string: "https://s3.example.com/bucket/trnscrb/file.mp3")!
        let presigned: URL = signer.presignedURL(for: baseURL, expiration: 3600, date: fixedDate)
        #expect(presigned.path == "/bucket/trnscrb/file.mp3")
    }

    @Test func presignedURLUsesCorrectAlgorithm() {
        let baseURL: URL = URL(string: "https://s3.example.com/bucket/key")!
        let presigned: URL = signer.presignedURL(for: baseURL, date: fixedDate)
        let components: URLComponents = URLComponents(url: presigned, resolvingAgainstBaseURL: false)!
        let algorithm: String? = components.queryItems?.first { $0.name == "X-Amz-Algorithm" }?.value
        #expect(algorithm == "AWS4-HMAC-SHA256")
    }

    @Test func presignedURLIsDeterministic() {
        let baseURL: URL = URL(string: "https://s3.example.com/bucket/key")!
        let url1: URL = signer.presignedURL(for: baseURL, date: fixedDate)
        let url2: URL = signer.presignedURL(for: baseURL, date: fixedDate)
        #expect(url1 == url2)
    }

    // MARK: - SHA256

    @Test func sha256OfEmptyString() {
        let hash: String = S3Signer.sha256("")
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func sha256OfKnownInput() {
        let hash: String = S3Signer.sha256("hello")
        #expect(hash == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
```

### Step 3: Run tests to verify they fail

Run: `swift test --filter S3SignerTests 2>&1 | tail -20`
Expected: Compilation error — `S3Signer` doesn't exist yet.

### Step 4: Implement S3Signer

Create `trnscrb/Infrastructure/Storage/S3Signer.swift`:

```swift
import CryptoKit
import Foundation

/// AWS Signature V4 signer for S3-compatible storage.
///
/// Signs HTTP requests and generates presigned URLs using HMAC-SHA256.
/// Supports any S3-compatible provider (AWS, Hetzner, Cloudflare R2, etc.).
public struct S3Signer: Sendable {
    /// Payload hash value for unsigned payloads (streaming uploads, presigned URLs).
    public static let unsignedPayload: String = "UNSIGNED-PAYLOAD"

    /// S3 access key identifier.
    private let accessKey: String
    /// S3 secret access key.
    private let secretKey: String
    /// S3 region (e.g., "us-east-1", "auto").
    private let region: String

    /// Creates a signer with the given credentials.
    public init(accessKey: String, secretKey: String, region: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
    }

    // MARK: - Public API

    /// Signs an HTTP request with AWS Signature V4.
    /// - Parameters:
    ///   - request: The request to sign (modified in-place).
    ///   - date: Signing timestamp (defaults to now).
    ///   - payloadHash: SHA256 hex digest of the request body, or `unsignedPayload`.
    public func sign(
        _ request: inout URLRequest,
        date: Date = Date(),
        payloadHash: String
    ) {
        guard let url = request.url, let host = url.host else { return }

        let amzDate: String = Self.amzDateString(date)
        let dateStamp: String = Self.dateStampString(date)
        let scope: String = "\(dateStamp)/\(region)/s3/aws4_request"

        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        let signedHeaders: String = "host;x-amz-content-sha256;x-amz-date"
        let headers: [(String, String)] = [
            ("host", host),
            ("x-amz-content-sha256", payloadHash),
            ("x-amz-date", amzDate)
        ]

        let canonical: String = canonicalRequest(
            method: request.httpMethod ?? "GET",
            path: url.path.isEmpty ? "/" : url.path,
            query: Self.canonicalQueryString(from: url),
            headers: headers,
            signedHeaders: signedHeaders,
            payloadHash: payloadHash
        )

        let sts: String = stringToSign(amzDate: amzDate, scope: scope, canonicalRequest: canonical)
        let key: SymmetricKey = signingKey(dateStamp: dateStamp)
        let sig: String = signature(stringToSign: sts, signingKey: key)

        let auth: String = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), " +
            "SignedHeaders=\(signedHeaders), Signature=\(sig)"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
    }

    /// Generates a presigned GET URL valid for the specified duration.
    /// - Parameters:
    ///   - url: The S3 object URL to sign.
    ///   - expiration: Validity in seconds (default: 3600).
    ///   - date: Signing timestamp (defaults to now).
    /// - Returns: A presigned URL with embedded authentication.
    public func presignedURL(
        for url: URL,
        expiration: Int = 3600,
        date: Date = Date()
    ) -> URL {
        guard let host = url.host else { return url }

        let amzDate: String = Self.amzDateString(date)
        let dateStamp: String = Self.dateStampString(date)
        let scope: String = "\(dateStamp)/\(region)/s3/aws4_request"
        let credential: String = "\(accessKey)/\(scope)"

        var components: URLComponents = URLComponents(
            url: url, resolvingAgainstBaseURL: false
        ) ?? URLComponents()

        // Pre-signing query parameters (sorted alphabetically for canonical request)
        components.queryItems = [
            URLQueryItem(name: "X-Amz-Algorithm", value: "AWS4-HMAC-SHA256"),
            URLQueryItem(name: "X-Amz-Credential", value: credential),
            URLQueryItem(name: "X-Amz-Date", value: amzDate),
            URLQueryItem(name: "X-Amz-Expires", value: "\(expiration)"),
            URLQueryItem(name: "X-Amz-SignedHeaders", value: "host")
        ]

        let queryString: String = components.queryItems!
            .sorted { $0.name < $1.name }
            .map { "\(Self.uriEncode($0.name))=\(Self.uriEncode($0.value ?? ""))" }
            .joined(separator: "&")

        let path: String = url.path.isEmpty ? "/" : url.path
        let canonical: String = canonicalRequest(
            method: "GET",
            path: path,
            query: queryString,
            headers: [("host", host)],
            signedHeaders: "host",
            payloadHash: Self.unsignedPayload
        )

        let sts: String = stringToSign(amzDate: amzDate, scope: scope, canonicalRequest: canonical)
        let key: SymmetricKey = signingKey(dateStamp: dateStamp)
        let sig: String = signature(stringToSign: sts, signingKey: key)

        components.queryItems?.append(URLQueryItem(name: "X-Amz-Signature", value: sig))
        return components.url ?? url
    }

    // MARK: - Internal (visible to tests via @testable import)

    /// Computes SHA256 hex digest of a string.
    static func sha256(_ string: String) -> String {
        let hash = CryptoKit.SHA256.hash(data: Data(string.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private

    private func canonicalRequest(
        method: String,
        path: String,
        query: String,
        headers: [(String, String)],
        signedHeaders: String,
        payloadHash: String
    ) -> String {
        let canonicalHeaders: String = headers
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0):\($0.1)" }
            .joined(separator: "\n")
        return [method, path, query, canonicalHeaders, "", signedHeaders, payloadHash]
            .joined(separator: "\n")
    }

    private func stringToSign(amzDate: String, scope: String, canonicalRequest: String) -> String {
        ["AWS4-HMAC-SHA256", amzDate, scope, Self.sha256(canonicalRequest)]
            .joined(separator: "\n")
    }

    private func signingKey(dateStamp: String) -> SymmetricKey {
        let kDate: Data = Self.hmac(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion: Data = Self.hmac(key: kDate, data: Data(region.utf8))
        let kService: Data = Self.hmac(key: kRegion, data: Data("s3".utf8))
        let kSigning: Data = Self.hmac(key: kService, data: Data("aws4_request".utf8))
        return SymmetricKey(data: kSigning)
    }

    private func signature(stringToSign: String, signingKey: SymmetricKey) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: signingKey)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmac(key: Data, data: Data) -> Data {
        let symmetricKey: SymmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac)
    }

    static func amzDateString(_ date: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func dateStampString(_ date: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func canonicalQueryString(from url: URL) -> String {
        let items: [URLQueryItem] = URLComponents(
            url: url, resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        return items
            .sorted { $0.name < $1.name }
            .map { "\(uriEncode($0.name))=\(uriEncode($0.value ?? ""))" }
            .joined(separator: "&")
    }

    private static func uriEncode(_ string: String) -> String {
        var allowed: CharacterSet = .alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
```

### Step 5: Run tests to verify they pass

Run: `swift test --filter S3SignerTests 2>&1 | tail -20`
Expected: All 8 tests pass.

### Step 6: Lint

Run: `swiftlint lint trnscrb/Infrastructure/Storage/S3Signer.swift 2>&1`
Expected: No violations.

### Step 7: Commit

```bash
git add Tests/Helpers/ trnscrb/Infrastructure/Storage/S3Signer.swift Tests/Infrastructure/S3SignerTests.swift
git commit -m "feat(infra): add S3Signer with AWS Signature V4 and shared test helpers"
```

---

## Task 2: S3Client — StorageGateway Implementation (TDD)

**Files:**
- Create: `trnscrb/Infrastructure/Storage/S3Client.swift`
- Create: `Tests/Infrastructure/S3ClientTests.swift`

**Context:** S3Client implements `StorageGateway`. It fetches credentials from `SettingsGateway` at call time, uses `S3Signer` for request signing, and `URLSession` for HTTP. Path-style URLs: `https://{endpoint}/{bucket}/{key}`. ListObjectsV2 response is XML parsed with `XMLParser`. Tests use `MockURLProtocol` to intercept HTTP calls.

### Step 1: Write tests

Create `Tests/Infrastructure/S3ClientTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

struct S3ClientTests {
    private func makeClient(
        endpoint: String = "https://s3.example.com",
        accessKey: String = "AKID",
        secretKey: String = "SECRET",
        bucket: String = "test-bucket",
        region: String = "us-east-1",
        pathPrefix: String = "trnscrb/"
    ) -> (S3Client, MockSettingsGateway) {
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings = AppSettings(
            s3EndpointURL: endpoint,
            s3AccessKey: accessKey,
            s3BucketName: bucket,
            s3Region: region,
            s3PathPrefix: pathPrefix
        )
        gateway.secrets[.s3SecretKey] = secretKey
        let session: URLSession = makeMockURLSession()
        let client: S3Client = S3Client(settingsGateway: gateway, urlSession: session)
        return (client, gateway)
    }

    // MARK: - Upload

    @Test func uploadSendsPUTRequest() async throws {
        let (client, _) = makeClient()
        let tempFile: URL = FileManager.default.temporaryDirectory.appending(path: "test.mp3")
        try Data("audio-content".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        MockURLProtocol.requestHandler = { request in
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
        let client: S3Client = S3Client(settingsGateway: gateway, urlSession: makeMockURLSession())
        let tempFile: URL = FileManager.default.temporaryDirectory.appending(path: "test.mp3")
        try Data("x".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        await #expect(throws: S3Error.self) {
            _ = try await client.upload(fileURL: tempFile, key: "k")
        }
    }

    // MARK: - Delete

    @Test func deleteSendsDELETERequest() async throws {
        let (client, _) = makeClient()

        MockURLProtocol.requestHandler = { request in
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
        let (client, _) = makeClient()
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

        MockURLProtocol.requestHandler = { request in
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
        let (client, _) = makeClient()
        let xmlResponse: String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListBucketResult></ListBucketResult>
        """

        MockURLProtocol.requestHandler = { _ in
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
```

### Step 2: Run tests to verify they fail

Run: `swift test --filter S3ClientTests 2>&1 | tail -20`
Expected: Compilation error — `S3Client` doesn't exist yet.

### Step 3: Implement S3Client

Create `trnscrb/Infrastructure/Storage/S3Client.swift`:

```swift
import Foundation

/// Errors from S3 storage operations.
public enum S3Error: Error, Sendable {
    /// Required S3 configuration is missing or incomplete.
    case invalidConfiguration(String)
    /// S3 request failed with a non-success HTTP status.
    case requestFailed(statusCode: Int, body: String)
}

/// S3-compatible object storage client implementing `StorageGateway`.
///
/// Uses path-style URLs: `https://{endpoint}/{bucket}/{key}`.
/// Fetches credentials from `SettingsGateway` on each call so
/// settings changes take effect immediately.
public struct S3Client: StorageGateway {
    /// Gateway for reading S3 credentials and configuration.
    private let settingsGateway: any SettingsGateway
    /// URL session for HTTP requests.
    private let urlSession: URLSession

    /// Creates an S3 client.
    /// - Parameters:
    ///   - settingsGateway: Provides S3 credentials and bucket config.
    ///   - urlSession: URL session for HTTP requests (injectable for testing).
    public init(settingsGateway: any SettingsGateway, urlSession: URLSession = .shared) {
        self.settingsGateway = settingsGateway
        self.urlSession = urlSession
    }

    /// Uploads a local file to S3 and returns a presigned GET URL.
    public func upload(fileURL: URL, key: String) async throws -> URL {
        let (settings, secretKey, signer) = try await loadConfig()
        let objectURL: URL = Self.objectURL(endpoint: settings.s3EndpointURL, bucket: settings.s3BucketName, key: key)
        let fileData: Data = try Data(contentsOf: fileURL)
        let payloadHash: String = S3Signer.sha256(fileData)

        var request: URLRequest = URLRequest(url: objectURL)
        request.httpMethod = "PUT"
        request.httpBody = fileData
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        signer.sign(&request, payloadHash: payloadHash)

        let (data, response) = try await urlSession.data(for: request)
        try Self.validateResponse(response, data: data)

        return signer.presignedURL(for: objectURL)
    }

    /// Deletes an object from S3.
    public func delete(key: String) async throws {
        let (settings, _, signer) = try await loadConfig()
        let objectURL: URL = Self.objectURL(endpoint: settings.s3EndpointURL, bucket: settings.s3BucketName, key: key)

        var request: URLRequest = URLRequest(url: objectURL)
        request.httpMethod = "DELETE"
        signer.sign(&request, payloadHash: S3Signer.unsignedPayload)

        let (data, response) = try await urlSession.data(for: request)
        try Self.validateResponse(response, data: data, acceptedCodes: [200, 204])
    }

    /// Lists object keys created before the given cutoff date.
    public func listCreatedBefore(_ cutoff: Date) async throws -> [String] {
        let (settings, _, signer) = try await loadConfig()
        let baseURL: URL = URL(string: "\(settings.s3EndpointURL)/\(settings.s3BucketName)")!
        var components: URLComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "prefix", value: settings.s3PathPrefix)
        ]

        var request: URLRequest = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        signer.sign(&request, payloadHash: S3Signer.unsignedPayload)

        let (data, response) = try await urlSession.data(for: request)
        try Self.validateResponse(response, data: data)

        let objects: [S3Object] = Self.parseListResponse(data)
        return objects.filter { $0.lastModified < cutoff }.map(\.key)
    }

    // MARK: - Private helpers

    private func loadConfig() async throws -> (AppSettings, String, S3Signer) {
        let settings: AppSettings = try await settingsGateway.loadSettings()
        guard let secretKey: String = try await settingsGateway.getSecret(for: .s3SecretKey) else {
            throw S3Error.invalidConfiguration("S3 secret key not configured")
        }
        guard settings.isS3Configured else {
            throw S3Error.invalidConfiguration("S3 endpoint, access key, or bucket not configured")
        }
        let signer: S3Signer = S3Signer(
            accessKey: settings.s3AccessKey,
            secretKey: secretKey,
            region: settings.s3Region
        )
        return (settings, secretKey, signer)
    }

    private static func objectURL(endpoint: String, bucket: String, key: String) -> URL {
        URL(string: "\(endpoint)/\(bucket)/\(key)")!
    }

    private static func validateResponse(
        _ response: URLResponse,
        data: Data,
        acceptedCodes: Set<Int> = [200]
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw S3Error.requestFailed(statusCode: 0, body: "Not an HTTP response")
        }
        guard acceptedCodes.contains(http.statusCode) else {
            let body: String = String(data: data, encoding: .utf8) ?? ""
            throw S3Error.requestFailed(statusCode: http.statusCode, body: body)
        }
    }

    // MARK: - XML parsing for ListObjectsV2

    private struct S3Object {
        let key: String
        let lastModified: Date
    }

    private static func parseListResponse(_ data: Data) -> [S3Object] {
        let parser: ListObjectsParser = ListObjectsParser()
        let xmlParser: XMLParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.objects
    }
}

// MARK: - ListObjectsV2 XML parser

private final class ListObjectsParser: NSObject, XMLParserDelegate {
    struct ParsedObject {
        let key: String
        let lastModified: Date
    }

    var objects: [S3Client.S3Object] = []
    private var currentElement: String = ""
    private var currentKey: String = ""
    private var currentLastModified: String = ""
    private var insideContents: Bool = false

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "Contents" {
            insideContents = true
            currentKey = ""
            currentLastModified = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideContents else { return }
        switch currentElement {
        case "Key": currentKey += string
        case "LastModified": currentLastModified += string
        default: break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if elementName == "Contents" {
            insideContents = false
            if !currentKey.isEmpty,
               let date = Self.dateFormatter.date(from: currentLastModified) {
                objects.append(S3Client.S3Object(key: currentKey, lastModified: date))
            }
        }
        currentElement = ""
    }
}

/// Extension for computing SHA256 of Data.
extension S3Signer {
    /// Computes SHA256 hex digest of raw data.
    static func sha256(_ data: Data) -> String {
        let hash = CryptoKit.SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
```

### Step 4: Run tests to verify they pass

Run: `swift test --filter S3ClientTests 2>&1 | tail -20`
Expected: All 5 tests pass.

### Step 5: Lint

Run: `swiftlint lint trnscrb/Infrastructure/Storage/ 2>&1`
Expected: No violations.

### Step 6: Commit

```bash
git add trnscrb/Infrastructure/Storage/S3Client.swift Tests/Infrastructure/S3ClientTests.swift
git commit -m "feat(infra): add S3Client implementing StorageGateway"
```

---

## Task 3: Delivery Implementations (TDD)

**Files:**
- Create: `trnscrb/Infrastructure/Delivery/ClipboardDelivery.swift`
- Create: `trnscrb/Infrastructure/Delivery/FileDelivery.swift`
- Create: `Tests/Infrastructure/DeliveryTests.swift`

**Context:** Two `DeliveryGateway` implementations. `ClipboardDelivery` copies markdown to `NSPasteboard.general`. `FileDelivery` writes a `.md` file to the configured save folder, appending a timestamp suffix if the file already exists. Both are simple — combined into one task.

### Step 1: Write tests

Create `Tests/Infrastructure/DeliveryTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

private func makeResult(
    markdown: String = "# Test",
    fileName: String = "recording.mp3"
) -> TranscriptionResult {
    TranscriptionResult(markdown: markdown, sourceFileName: fileName, sourceFileType: .audio)
}

// MARK: - ClipboardDelivery

struct ClipboardDeliveryTests {
    @Test func deliverCopiesMarkdownToClipboard() async throws {
        let delivery: ClipboardDelivery = ClipboardDelivery()
        let result: TranscriptionResult = makeResult(markdown: "# Hello World")
        try await delivery.deliver(result: result)

        let clipboard: String? = NSPasteboard.general.string(forType: .string)
        #expect(clipboard == "# Hello World")
    }

    @Test func deliverOverwritesPreviousClipboard() async throws {
        let delivery: ClipboardDelivery = ClipboardDelivery()
        try await delivery.deliver(result: makeResult(markdown: "first"))
        try await delivery.deliver(result: makeResult(markdown: "second"))

        let clipboard: String? = NSPasteboard.general.string(forType: .string)
        #expect(clipboard == "second")
    }
}

// MARK: - FileDelivery

struct FileDeliveryTests {
    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
    }

    private func makeDelivery(saveFolderPath: String) -> (FileDelivery, MockSettingsGateway) {
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings.saveFolderPath = saveFolderPath
        let delivery: FileDelivery = FileDelivery(settingsGateway: gateway)
        return (delivery, gateway)
    }

    @Test func deliverCreatesMarkdownFile() async throws {
        let tempDir: URL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let (delivery, _) = makeDelivery(saveFolderPath: tempDir.path())

        try await delivery.deliver(result: makeResult(markdown: "# Notes", fileName: "meeting.mp3"))

        let fileURL: URL = tempDir.appending(path: "meeting.md")
        let content: String = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content == "# Notes")
    }

    @Test func deliverCreatesFolderIfMissing() async throws {
        let tempDir: URL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let (delivery, _) = makeDelivery(saveFolderPath: tempDir.path())

        #expect(!FileManager.default.fileExists(atPath: tempDir.path()))
        try await delivery.deliver(result: makeResult())
        #expect(FileManager.default.fileExists(atPath: tempDir.path()))
    }

    @Test func deliverAppendsSuffixWhenFileExists() async throws {
        let tempDir: URL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let (delivery, _) = makeDelivery(saveFolderPath: tempDir.path())

        // First delivery — creates recording.md
        try await delivery.deliver(result: makeResult(markdown: "first", fileName: "recording.mp3"))
        // Second delivery — should create recording-TIMESTAMP.md
        try await delivery.deliver(result: makeResult(markdown: "second", fileName: "recording.mp3"))

        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: tempDir.path())
        #expect(files.count == 2)
        #expect(files.contains("recording.md"))
        #expect(files.contains(where: { $0.hasPrefix("recording-") && $0.hasSuffix(".md") }))
    }

    @Test func deliverStripsOriginalExtension() async throws {
        let tempDir: URL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let (delivery, _) = makeDelivery(saveFolderPath: tempDir.path())

        try await delivery.deliver(result: makeResult(fileName: "scan.pdf"))

        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: tempDir.path())
        #expect(files == ["scan.md"])
    }
}
```

### Step 2: Run tests to verify they fail

Run: `swift test --filter "ClipboardDeliveryTests|FileDeliveryTests" 2>&1 | tail -20`
Expected: Compilation error — types don't exist yet.

### Step 3: Implement ClipboardDelivery

Create `trnscrb/Infrastructure/Delivery/ClipboardDelivery.swift`:

```swift
import AppKit

/// Delivers transcription results by copying markdown to the system clipboard.
public struct ClipboardDelivery: DeliveryGateway {
    /// Creates a clipboard delivery handler.
    public init() {}

    /// Copies the markdown content to the system clipboard.
    public func deliver(result: TranscriptionResult) async throws {
        let pasteboard: NSPasteboard = .general
        pasteboard.clearContents()
        pasteboard.setString(result.markdown, forType: .string)
    }
}
```

### Step 4: Implement FileDelivery

Create `trnscrb/Infrastructure/Delivery/FileDelivery.swift`:

```swift
import Foundation

/// Errors from file delivery operations.
public enum FileDeliveryError: Error, Sendable {
    /// Could not write the markdown file.
    case writeFailed(String)
}

/// Delivers transcription results by saving markdown as a `.md` file.
///
/// File is saved to the folder configured in `AppSettings.saveFolderPath`.
/// If a file with the same name exists, a timestamp suffix is appended.
public struct FileDelivery: DeliveryGateway {
    /// Gateway for reading the save folder path from settings.
    private let settingsGateway: any SettingsGateway

    /// Creates a file delivery handler.
    /// - Parameter settingsGateway: Provides the configured save folder path.
    public init(settingsGateway: any SettingsGateway) {
        self.settingsGateway = settingsGateway
    }

    /// Saves the markdown content as a `.md` file in the configured folder.
    public func deliver(result: TranscriptionResult) async throws {
        let settings: AppSettings = try await settingsGateway.loadSettings()
        let folderPath: String = (settings.saveFolderPath as NSString).expandingTildeInPath
        let folderURL: URL = URL(filePath: folderPath)

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let baseName: String = (result.sourceFileName as NSString).deletingPathExtension
        let fileURL: URL = outputFileURL(folder: folderURL, baseName: baseName)

        try result.markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Determines the output file URL, appending a timestamp if the file already exists.
    private func outputFileURL(folder: URL, baseName: String) -> URL {
        let primary: URL = folder.appending(path: "\(baseName).md")
        guard FileManager.default.fileExists(atPath: primary.path()) else {
            return primary
        }
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let timestamp: String = formatter.string(from: Date())
        return folder.appending(path: "\(baseName)-\(timestamp).md")
    }
}
```

### Step 5: Run tests to verify they pass

Run: `swift test --filter "ClipboardDeliveryTests|FileDeliveryTests" 2>&1 | tail -20`
Expected: All 6 tests pass.

### Step 6: Lint

Run: `swiftlint lint trnscrb/Infrastructure/Delivery/ 2>&1`
Expected: No violations.

### Step 7: Commit

```bash
git add trnscrb/Infrastructure/Delivery/ Tests/Infrastructure/DeliveryTests.swift
git commit -m "feat(infra): add ClipboardDelivery and FileDelivery"
```

---

## Task 4: MistralAudioProvider (TDD)

**Files:**
- Create: `trnscrb/Infrastructure/Transcription/MistralError.swift`
- Create: `trnscrb/Infrastructure/Transcription/MistralAudioProvider.swift`
- Create: `Tests/Infrastructure/MistralAudioProviderTests.swift`

**Context:** Implements `TranscriptionGateway` for audio files. Calls Mistral's audio transcription API: `POST https://api.mistral.ai/v1/audio/transcriptions` with `application/json` body containing `model` + `file_url`. Model name: `voxtral-mini-latest`. Response JSON has a `text` field with the transcript. API key fetched from `SettingsGateway` on each call. Timeout: 300s (5 min, generous for long audio). `MistralError` is shared between both Mistral providers.

### Step 1: Write tests

Create `Tests/Infrastructure/MistralAudioProviderTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

struct MistralAudioProviderTests {
    private func makeProvider(
        apiKey: String? = "test-api-key"
    ) -> MistralAudioProvider {
        let gateway: MockSettingsGateway = MockSettingsGateway()
        if let apiKey {
            gateway.secrets[.mistralAPIKey] = apiKey
        }
        return MistralAudioProvider(settingsGateway: gateway, urlSession: makeMockURLSession())
    }

    // MARK: - Supported extensions

    @Test func supportedExtensionsMatchAudioFileType() {
        let provider: MistralAudioProvider = makeProvider()
        #expect(provider.supportedExtensions == FileType.audioExtensions)
    }

    // MARK: - Request format

    @Test func processCallsCorrectEndpoint() async throws {
        let provider: MistralAudioProvider = makeProvider()

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/audio/transcriptions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")

            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            #expect(body["model"] as? String == "voxtral-mini-latest")
            #expect(body["file_url"] as? String == "https://s3.example.com/bucket/file.mp3")

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
        let provider: MistralAudioProvider = makeProvider(apiKey: nil)
        await #expect(throws: MistralError.self) {
            _ = try await provider.process(sourceURL: URL(string: "https://example.com/f.mp3")!)
        }
    }

    @Test func processThrowsOnNon200Response() async {
        let provider: MistralAudioProvider = makeProvider()

        MockURLProtocol.requestHandler = { request in
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
        let provider: MistralAudioProvider = makeProvider()

        MockURLProtocol.requestHandler = { request in
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
```

### Step 2: Run tests to verify they fail

Run: `swift test --filter MistralAudioProviderTests 2>&1 | tail -20`
Expected: Compilation error.

### Step 3: Create MistralError (shared)

Create `trnscrb/Infrastructure/Transcription/MistralError.swift`:

```swift
import Foundation

/// Errors from Mistral API operations.
///
/// Shared between `MistralAudioProvider` and `MistralOCRProvider`.
public enum MistralError: Error, Sendable {
    /// No Mistral API key configured in settings.
    case missingAPIKey
    /// API returned a non-200 HTTP status.
    case requestFailed(statusCode: Int, body: String)
    /// API response could not be parsed.
    case invalidResponse(String)
}
```

### Step 4: Implement MistralAudioProvider

Create `trnscrb/Infrastructure/Transcription/MistralAudioProvider.swift`:

```swift
import Foundation

/// Transcribes audio files via the Mistral Voxtral API.
///
/// Endpoint: `POST https://api.mistral.ai/v1/audio/transcriptions`
/// Model: `voxtral-mini-latest`
/// Accepts a presigned S3 URL via the `file_url` parameter.
public struct MistralAudioProvider: TranscriptionGateway {
    /// Audio file extensions this provider handles.
    public var supportedExtensions: Set<String> { FileType.audioExtensions }

    /// Gateway for retrieving the Mistral API key.
    private let settingsGateway: any SettingsGateway
    /// URL session for HTTP requests.
    private let urlSession: URLSession

    /// Creates an audio transcription provider.
    /// - Parameters:
    ///   - settingsGateway: Provides the Mistral API key from Keychain.
    ///   - urlSession: URL session for HTTP requests (injectable for testing).
    public init(settingsGateway: any SettingsGateway, urlSession: URLSession = .shared) {
        self.settingsGateway = settingsGateway
        self.urlSession = urlSession
    }

    /// Transcribes audio at the given presigned URL and returns the text.
    public func process(sourceURL: URL) async throws -> String {
        let apiKey: String = try await loadAPIKey()

        let body: [String: Any] = [
            "model": "voxtral-mini-latest",
            "file_url": sourceURL.absoluteString
        ]

        var request: URLRequest = URLRequest(
            url: URL(string: "https://api.mistral.ai/v1/audio/transcriptions")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MistralError.invalidResponse("Not an HTTP response")
        }
        guard http.statusCode == 200 else {
            let responseBody: String = String(data: data, encoding: .utf8) ?? ""
            throw MistralError.requestFailed(statusCode: http.statusCode, body: responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw MistralError.invalidResponse("Missing 'text' field in response")
        }

        return text
    }

    /// Retrieves the Mistral API key from the Keychain via SettingsGateway.
    private func loadAPIKey() async throws -> String {
        guard let apiKey: String = try await settingsGateway.getSecret(for: .mistralAPIKey),
              !apiKey.isEmpty else {
            throw MistralError.missingAPIKey
        }
        return apiKey
    }
}
```

### Step 5: Run tests to verify they pass

Run: `swift test --filter MistralAudioProviderTests 2>&1 | tail -20`
Expected: All 5 tests pass.

### Step 6: Lint

Run: `swiftlint lint trnscrb/Infrastructure/Transcription/ 2>&1`
Expected: No violations.

### Step 7: Commit

```bash
git add trnscrb/Infrastructure/Transcription/MistralError.swift trnscrb/Infrastructure/Transcription/MistralAudioProvider.swift Tests/Infrastructure/MistralAudioProviderTests.swift
git commit -m "feat(infra): add MistralAudioProvider for Voxtral transcription"
```

---

## Task 5: MistralOCRProvider (TDD)

**Files:**
- Create: `trnscrb/Infrastructure/Transcription/MistralOCRProvider.swift`
- Create: `Tests/Infrastructure/MistralOCRProviderTests.swift`

**Context:** Implements `TranscriptionGateway` for PDFs and images. Calls Mistral's OCR API: `POST https://api.mistral.ai/v1/ocr`. Model: `mistral-ocr-latest`. Determines document type from URL path extension: PDFs use `DocumentURLChunk` (`"type": "document_url"`), images use `ImageURLChunk` (`"type": "image_url"`). Response has `pages` array — concatenate `markdown` from each page. Timeout: 120s. Reuses `MistralError` from Task 4.

### Step 1: Write tests

Create `Tests/Infrastructure/MistralOCRProviderTests.swift`:

```swift
import Foundation
import Testing

@testable import trnscrb

struct MistralOCRProviderTests {
    private func makeProvider(
        apiKey: String? = "test-api-key"
    ) -> MistralOCRProvider {
        let gateway: MockSettingsGateway = MockSettingsGateway()
        if let apiKey {
            gateway.secrets[.mistralAPIKey] = apiKey
        }
        return MistralOCRProvider(settingsGateway: gateway, urlSession: makeMockURLSession())
    }

    // MARK: - Supported extensions

    @Test func supportedExtensionsCoversPDFAndImages() {
        let provider: MistralOCRProvider = makeProvider()
        let expected: Set<String> = FileType.pdfExtensions.union(FileType.imageExtensions)
        #expect(provider.supportedExtensions == expected)
    }

    // MARK: - PDF request

    @Test func processUsesDocumentURLChunkForPDF() async throws {
        let provider: MistralOCRProvider = makeProvider()

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/ocr")
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            #expect(body["model"] as? String == "mistral-ocr-latest")
            let doc = body["document"] as! [String: Any]
            #expect(doc["type"] as? String == "document_url")
            #expect(doc["documentUrl"] as? String == "https://s3.example.com/bucket/doc.pdf")

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
        let provider: MistralOCRProvider = makeProvider()

        MockURLProtocol.requestHandler = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let doc = body["document"] as! [String: Any]
            #expect(doc["type"] as? String == "image_url")
            let imageURL = doc["image_url"] as! [String: Any]
            #expect(imageURL["url"] as? String == "https://s3.example.com/bucket/photo.jpg")

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
        let provider: MistralOCRProvider = makeProvider(apiKey: nil)
        await #expect(throws: MistralError.self) {
            _ = try await provider.process(sourceURL: URL(string: "https://example.com/doc.pdf")!)
        }
    }

    @Test func processThrowsOnNon200Response() async {
        let provider: MistralOCRProvider = makeProvider()
        MockURLProtocol.requestHandler = { request in
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
        let provider: MistralOCRProvider = makeProvider()
        MockURLProtocol.requestHandler = { request in
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
        let provider: MistralOCRProvider = makeProvider()
        MockURLProtocol.requestHandler = { request in
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
```

### Step 2: Run tests to verify they fail

Run: `swift test --filter MistralOCRProviderTests 2>&1 | tail -20`
Expected: Compilation error.

### Step 3: Implement MistralOCRProvider

Create `trnscrb/Infrastructure/Transcription/MistralOCRProvider.swift`:

```swift
import Foundation

/// Processes PDFs and images via the Mistral OCR API.
///
/// Endpoint: `POST https://api.mistral.ai/v1/ocr`
/// Model: `mistral-ocr-latest`
/// PDFs use `DocumentURLChunk` (`type: "document_url"`).
/// Images use `ImageURLChunk` (`type: "image_url"`).
/// Response pages' markdown is concatenated with double newlines.
public struct MistralOCRProvider: TranscriptionGateway {
    /// PDF and image file extensions this provider handles.
    public var supportedExtensions: Set<String> {
        FileType.pdfExtensions.union(FileType.imageExtensions)
    }

    /// Gateway for retrieving the Mistral API key.
    private let settingsGateway: any SettingsGateway
    /// URL session for HTTP requests.
    private let urlSession: URLSession

    /// Creates an OCR provider.
    /// - Parameters:
    ///   - settingsGateway: Provides the Mistral API key from Keychain.
    ///   - urlSession: URL session for HTTP requests (injectable for testing).
    public init(settingsGateway: any SettingsGateway, urlSession: URLSession = .shared) {
        self.settingsGateway = settingsGateway
        self.urlSession = urlSession
    }

    /// Processes a PDF or image at the given presigned URL and returns markdown.
    public func process(sourceURL: URL) async throws -> String {
        let apiKey: String = try await loadAPIKey()

        let body: [String: Any] = [
            "model": "mistral-ocr-latest",
            "document": documentChunk(for: sourceURL)
        ]

        var request: URLRequest = URLRequest(
            url: URL(string: "https://api.mistral.ai/v1/ocr")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MistralError.invalidResponse("Not an HTTP response")
        }
        guard http.statusCode == 200 else {
            let responseBody: String = String(data: data, encoding: .utf8) ?? ""
            throw MistralError.requestFailed(statusCode: http.statusCode, body: responseBody)
        }

        return try parsePages(data)
    }

    // MARK: - Private

    /// Retrieves the Mistral API key from the Keychain via SettingsGateway.
    private func loadAPIKey() async throws -> String {
        guard let apiKey: String = try await settingsGateway.getSecret(for: .mistralAPIKey),
              !apiKey.isEmpty else {
            throw MistralError.missingAPIKey
        }
        return apiKey
    }

    /// Constructs the document chunk JSON based on the URL's file extension.
    private func documentChunk(for url: URL) -> [String: Any] {
        let ext: String = url.pathExtension.lowercased()
        if FileType.pdfExtensions.contains(ext) {
            return [
                "type": "document_url",
                "documentUrl": url.absoluteString
            ]
        } else {
            return [
                "type": "image_url",
                "image_url": ["url": url.absoluteString]
            ]
        }
    }

    /// Parses the OCR response, concatenating markdown from all pages.
    private func parsePages(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = json["pages"] as? [[String: Any]] else {
            throw MistralError.invalidResponse("Missing 'pages' field in OCR response")
        }
        let markdowns: [String] = pages.compactMap { $0["markdown"] as? String }
        guard !markdowns.isEmpty else {
            throw MistralError.invalidResponse("No markdown content in OCR response pages")
        }
        return markdowns.joined(separator: "\n\n")
    }
}
```

### Step 4: Run tests to verify they pass

Run: `swift test --filter MistralOCRProviderTests 2>&1 | tail -20`
Expected: All 7 tests pass.

### Step 5: Lint

Run: `swiftlint lint trnscrb/Infrastructure/Transcription/ 2>&1`
Expected: No violations.

### Step 6: Commit

```bash
git add trnscrb/Infrastructure/Transcription/MistralOCRProvider.swift Tests/Infrastructure/MistralOCRProviderTests.swift
git commit -m "feat(infra): add MistralOCRProvider for PDF and image OCR"
```

---

## Summary

| Task | Component | Tests | Files |
|------|-----------|-------|-------|
| 1 | S3Signer + test helpers | 8 | 4 new |
| 2 | S3Client | 5 | 2 new |
| 3 | ClipboardDelivery + FileDelivery | 6 | 3 new |
| 4 | MistralAudioProvider + MistralError | 5 | 3 new |
| 5 | MistralOCRProvider | 7 | 2 new |

**Total:** 31 new tests, 14 new files, 0 modified files. No external dependencies.

**After Phase 2:** All infrastructure components are implemented and tested. Every gateway protocol has a concrete implementation. Ready for Phase 3 (Integration) to wire `ProcessFileUseCase`, drag-and-drop, and the job queue.
