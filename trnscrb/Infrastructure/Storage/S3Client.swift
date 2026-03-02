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
    public func upload(
        fileURL: URL,
        key: String,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        let (settings, signer) = try await loadConfig()
        let objectURL: URL = try Self.objectURL(
            endpoint: settings.s3EndpointURL, bucket: settings.s3BucketName, key: key
        )
        let payloadHash: String = try S3Signer.sha256(fileURL: fileURL)

        var request: URLRequest = URLRequest(url: objectURL)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        signer.sign(&request, payloadHash: payloadHash)

        let (data, response) = try await uploadData(
            request: request,
            fileURL: fileURL,
            onProgress: onProgress
        )
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
        let baseURL: URL = try Self.bucketURL(
            endpoint: settings.s3EndpointURL,
            bucket: settings.s3BucketName
        )
        var continuationToken: String?
        var expiredKeys: [String] = []

        repeat {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw S3Error.invalidConfiguration("Invalid endpoint URL components")
            }
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "list-type", value: "2"),
                URLQueryItem(name: "prefix", value: settings.s3PathPrefix)
            ]
            if let continuationToken {
                queryItems.append(
                    URLQueryItem(name: "continuation-token", value: continuationToken)
                )
            }
            components.queryItems = queryItems

            guard let listURL = components.url else {
                throw S3Error.invalidConfiguration("Could not construct list URL")
            }

            var request: URLRequest = URLRequest(url: listURL)
            request.httpMethod = "GET"
            signer.sign(&request, payloadHash: S3Signer.unsignedPayload)

            let (data, response) = try await urlSession.data(for: request)
            try Self.validateResponse(response, data: data)

            let page: ListObjectsPage = Self.parseListResponse(data)
            expiredKeys.append(contentsOf: page.objects.filter { $0.lastModified < cutoff }.map(\.key))
            continuationToken = page.isTruncated ? page.nextContinuationToken : nil
        } while continuationToken != nil

        return expiredKeys
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

    private static func bucketURL(endpoint: String, bucket: String) throws -> URL {
        guard let endpointURL = URL(string: endpoint) else {
            throw S3Error.invalidConfiguration("Invalid endpoint URL")
        }
        return endpointURL.appendingPathComponent(bucket, isDirectory: false)
    }

    private static func objectURL(endpoint: String, bucket: String, key: String) throws -> URL {
        let baseURL: URL = try bucketURL(endpoint: endpoint, bucket: bucket)
        let segments: [String] = key.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let finalURL: URL = segments.reduce(baseURL) { partial, segment in
            partial.appendingPathComponent(segment, isDirectory: false)
        }
        return finalURL
    }

    private func uploadData(
        request: URLRequest,
        fileURL: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> (Data, URLResponse) {
        guard let onProgress else {
            return try await urlSession.upload(for: request, fromFile: fileURL)
        }

        let progressDelegate: UploadProgressDelegate = UploadProgressDelegate(onProgress: onProgress)
        let copiedConfiguration: URLSessionConfiguration = urlSession.configuration.copy() as? URLSessionConfiguration
            ?? .ephemeral
        let progressSession: URLSession = URLSession(
            configuration: copiedConfiguration,
            delegate: progressDelegate,
            delegateQueue: nil
        )

        onProgress(0)
        return try await withCheckedThrowingContinuation { continuation in
            let task: URLSessionUploadTask = progressSession.uploadTask(with: request, fromFile: fileURL) {
                data, response, error in
                progressSession.finishTasksAndInvalidate()
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(
                        throwing: S3Error.requestFailed(statusCode: 0, body: "Missing upload response")
                    )
                    return
                }
                onProgress(1)
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
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

    private static func parseListResponse(_ data: Data) -> ListObjectsPage {
        let delegate: ListObjectsParser = ListObjectsParser()
        let xmlParser: XMLParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        xmlParser.parse()
        return ListObjectsPage(
            objects: delegate.objects,
            isTruncated: delegate.isTruncated,
            nextContinuationToken: delegate.nextContinuationToken
        )
    }

    fileprivate struct ListObjectsPage {
        let objects: [S3Object]
        let isTruncated: Bool
        let nextContinuationToken: String?
    }
}

// MARK: - ListObjectsV2 XML parser

private final class ListObjectsParser: NSObject, XMLParserDelegate {
    var objects: [S3Client.S3Object] = []
    var isTruncated: Bool = false
    var nextContinuationToken: String?

    private var currentElement: String = ""
    private var currentKey: String = ""
    private var currentLastModified: String = ""
    private var currentTruncatedFlag: String = ""
    private var currentContinuationToken: String = ""
    private var insideContents: Bool = false
    private let fractionalFormatter: ISO8601DateFormatter = {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let plainFormatter: ISO8601DateFormatter = {
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
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
        let trimmed: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if insideContents {
            switch currentElement {
            case "Key": currentKey += trimmed
            case "LastModified": currentLastModified += trimmed
            default: break
            }
            return
        }

        switch currentElement {
        case "IsTruncated":
            currentTruncatedFlag += trimmed
        case "NextContinuationToken":
            currentContinuationToken += trimmed
        default:
            break
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
               let date = fractionalFormatter.date(from: currentLastModified)
                    ?? plainFormatter.date(from: currentLastModified) {
                objects.append(S3Client.S3Object(key: currentKey, lastModified: date))
            }
        } else if elementName == "IsTruncated" {
            isTruncated = currentTruncatedFlag.caseInsensitiveCompare("true") == .orderedSame
            currentTruncatedFlag = ""
        } else if elementName == "NextContinuationToken" {
            nextContinuationToken = currentContinuationToken.isEmpty ? nil : currentContinuationToken
            currentContinuationToken = ""
        }
        currentElement = ""
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress: Double = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(min(max(progress, 0), 1))
    }
}

/// Extensions for computing SHA256 digests.
extension S3Signer {
    /// Computes SHA256 hex digest of raw data.
    static func sha256(_ data: Data) -> String {
        let hash = CryptoKit.SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes SHA256 hex digest for a file without loading it fully into memory.
    static func sha256(fileURL: URL, chunkSize: Int = 64 * 1024) throws -> String {
        guard let stream: InputStream = InputStream(url: fileURL) else {
            throw S3Error.invalidConfiguration("Could not read file for hashing")
        }

        stream.open()
        defer { stream.close() }

        var hasher: CryptoKit.SHA256 = CryptoKit.SHA256()
        let buffer: UnsafeMutablePointer<UInt8> = .allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let readCount: Int = stream.read(buffer, maxLength: chunkSize)
            if readCount < 0 {
                throw stream.streamError ?? S3Error.invalidConfiguration("Failed to hash file")
            }
            if readCount == 0 {
                break
            }
            hasher.update(data: Data(bytes: buffer, count: readCount))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
