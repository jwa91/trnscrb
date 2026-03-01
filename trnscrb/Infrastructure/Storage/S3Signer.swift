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

        let queryString: String = components.queryItems
            .map { items in
                items
                    .sorted { $0.name < $1.name }
                    .map { "\(Self.uriEncode($0.name))=\(Self.uriEncode($0.value ?? ""))" }
                    .joined(separator: "&")
            } ?? ""

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
