import CryptoKit
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
        let (settings, signer) = try await loadConfig()
        let objectURL: URL = try Self.objectURL(
            endpoint: settings.s3EndpointURL, bucket: settings.s3BucketName, key: key
        )
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
        let (settings, signer) = try await loadConfig()
        let objectURL: URL = try Self.objectURL(
            endpoint: settings.s3EndpointURL, bucket: settings.s3BucketName, key: key
        )

        var request: URLRequest = URLRequest(url: objectURL)
        request.httpMethod = "DELETE"
        signer.sign(&request, payloadHash: S3Signer.unsignedPayload)

        let (data, response) = try await urlSession.data(for: request)
        try Self.validateResponse(response, data: data, acceptedCodes: [200, 204])
    }

    /// Lists object keys created before the given cutoff date.
    public func listCreatedBefore(_ cutoff: Date) async throws -> [String] {
        let (settings, signer) = try await loadConfig()
        guard let baseURL = URL(string: "\(settings.s3EndpointURL)/\(settings.s3BucketName)") else {
            throw S3Error.invalidConfiguration("Invalid endpoint URL")
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw S3Error.invalidConfiguration("Invalid endpoint URL components")
        }
        components.queryItems = [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "prefix", value: settings.s3PathPrefix)
        ]

        guard let listURL = components.url else {
            throw S3Error.invalidConfiguration("Could not construct list URL")
        }

        var request: URLRequest = URLRequest(url: listURL)
        request.httpMethod = "GET"
        signer.sign(&request, payloadHash: S3Signer.unsignedPayload)

        let (data, response) = try await urlSession.data(for: request)
        try Self.validateResponse(response, data: data)

        let objects: [S3Object] = Self.parseListResponse(data)
        return objects.filter { $0.lastModified < cutoff }.map(\.key)
    }

    // MARK: - Private helpers

    private func loadConfig() async throws -> (AppSettings, S3Signer) {
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
        return (settings, signer)
    }

    private static func objectURL(endpoint: String, bucket: String, key: String) throws -> URL {
        guard let url = URL(string: "\(endpoint)/\(bucket)/\(key)") else {
            throw S3Error.invalidConfiguration("Could not construct object URL")
        }
        return url
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

    fileprivate struct S3Object {
        let key: String
        let lastModified: Date
    }

    private static func parseListResponse(_ data: Data) -> [S3Object] {
        let delegate: ListObjectsParser = ListObjectsParser()
        let xmlParser: XMLParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        xmlParser.parse()
        return delegate.objects
    }
}

// MARK: - ListObjectsV2 XML parser

private final class ListObjectsParser: NSObject, XMLParserDelegate {
    var objects: [S3Client.S3Object] = []
    private var currentElement: String = ""
    private var currentKey: String = ""
    private var currentLastModified: String = ""
    private var insideContents: Bool = false

    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
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

/// Extension for computing SHA256 of raw `Data`.
extension S3Signer {
    /// Computes SHA256 hex digest of raw data.
    static func sha256(_ data: Data) -> String {
        let hash = CryptoKit.SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
