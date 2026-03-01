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
