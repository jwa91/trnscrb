import Foundation

/// Processes PDFs and images via the Mistral OCR API.
///
/// Endpoint: `POST https://api.mistral.ai/v1/ocr`
/// Model: `mistral-ocr-latest`
/// Remote PDFs use `DocumentURLChunk` (`type: "document_url"`).
/// Remote images use `ImageURLChunk` (`type: "image_url"`).
/// Local files are uploaded to `/v1/files` with purpose `ocr`, then processed by `file_id`.
/// Response pages' markdown is concatenated with double newlines.
public struct MistralOCRProvider: TranscriptionGateway {
    // swiftlint:disable:next force_unwrapping
    private static let endpoint: URL = URL(string: "https://api.mistral.ai/v1/ocr")!
    // swiftlint:disable:next force_unwrapping
    private static let filesEndpoint: URL = URL(string: "https://api.mistral.ai/v1/files")!
    /// This provider is selected when mode is Mistral.
    public let providerMode: ProviderMode = .mistral
    /// Mistral can process direct local files and remotely reachable URLs.
    public let supportedSourceKinds: Set<TranscriptionSourceKind> = [.localFile, .remoteURL]

    /// PDF and image file extensions this provider handles.
    public var supportedExtensions: Set<String> {
        FileType.pdfExtensions.union(FileType.imageExtensions)
    }

    /// Gateway for retrieving the Mistral API key.
    private let settingsGateway: any SettingsGateway
    /// URL session for HTTP requests.
    private let urlSession: URLSession
    /// Opens security-scoped file URLs when needed.
    private let fileAccess: any SecurityScopedFileAccessing

    /// Creates an OCR provider.
    /// - Parameters:
    ///   - settingsGateway: Provides the Mistral API key from Keychain.
    ///   - urlSession: URL session for HTTP requests (injectable for testing).
    ///   - fileAccess: Opens security-scoped file URLs for sandboxed reads.
    public init(
        settingsGateway: any SettingsGateway,
        urlSession: URLSession = .shared,
        fileAccess: any SecurityScopedFileAccessing = SecurityScopedFileAccess()
    ) {
        self.settingsGateway = settingsGateway
        self.urlSession = urlSession
        self.fileAccess = fileAccess
    }

    /// Processes a PDF or image from a local file URL or remote URL and returns markdown.
    public func process(sourceURL: URL) async throws -> String {
        let apiKey: String = try await loadAPIKey()
        let requestStartedAt: Date = Date()

        let document: [String: Any]
        if sourceURL.isFileURL {
            let fileID: String = try await uploadFileForOCR(
                apiKey: apiKey,
                fileURL: sourceURL
            )
            document = ["file_id": fileID]
        } else {
            document = documentChunk(for: sourceURL)
        }

        let body: [String: Any] = [
            "model": "mistral-ocr-latest",
            "document": document
        ]
        AppLog.network.info("Starting OCR request for \(LogRedaction.sourceURLSummary(sourceURL), privacy: .public)")

        var request: URLRequest = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MistralError.invalidResponse("Not an HTTP response")
        }
        AppLog.network.info("OCR response HTTP \(http.statusCode, privacy: .public)")
        guard http.statusCode == 200 else {
            let responseBody: String = String(data: data, encoding: .utf8) ?? ""
            throw MistralError.requestFailed(statusCode: http.statusCode, body: responseBody)
        }

        let markdown: String = try parsePages(data)
        let elapsedMs: Int = Int((Date().timeIntervalSince(requestStartedAt) * 1000).rounded())
        AppLog.network.info("OCR request finished in \(elapsedMs, privacy: .public) ms")
        return markdown
    }

    // MARK: - Private

    /// Retrieves the Mistral API key from the Keychain via SettingsGateway.
    private func loadAPIKey() async throws -> String {
        guard let apiKey: String = try await settingsGateway.getSecret(for: .mistralAPIKey)?
            .trimmedCredentialValue,
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
                "document_url": url.absoluteString
            ]
        } else {
            return [
                "type": "image_url",
                "image_url": url.absoluteString
            ]
        }
    }

    private func uploadFileForOCR(apiKey: String, fileURL: URL) async throws -> String {
        let preparedRequest: (request: URLRequest, bodyFile: FileBackedMultipartBody) = try makeFileUploadRequest(
            apiKey: apiKey,
            fileURL: fileURL
        )
        defer {
            preparedRequest.bodyFile.cleanup()
        }

        let (data, response) = try await urlSession.data(for: preparedRequest.request)
        guard let http = response as? HTTPURLResponse else {
            throw MistralError.invalidResponse("Not an HTTP response")
        }
        guard http.statusCode == 200 else {
            let responseBody: String = String(data: data, encoding: .utf8) ?? ""
            throw MistralError.requestFailed(statusCode: http.statusCode, body: responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileID: String = json["id"] as? String,
              !fileID.isEmpty else {
            throw MistralError.invalidResponse("Missing file id in files upload response")
        }
        return fileID
    }

    private func makeFileUploadRequest(
        apiKey: String,
        fileURL: URL
    ) throws -> (request: URLRequest, bodyFile: FileBackedMultipartBody) {
        let boundary: String = "Boundary-\(UUID().uuidString)"
        var request: URLRequest = URLRequest(url: Self.filesEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let fileName: String = fileURL.lastPathComponent.isEmpty ? "document" : fileURL.lastPathComponent
        let bodyFile: FileBackedMultipartBody = try FileBackedMultipartBodyBuilder.create(
            boundary: boundary,
            fields: [("purpose", "ocr")],
            fileFieldName: "file",
            fileURL: fileURL,
            fileName: fileName,
            mimeType: mimeType(for: fileURL.pathExtension),
            fileAccess: fileAccess,
            filePreparationErrorMessage: "Could not prepare local OCR file at \(fileName) for upload."
        )
        request.setValue(String(bodyFile.contentLength), forHTTPHeaderField: "Content-Length")
        request.httpBodyStream = try bodyFile.makeInputStream()
        request.timeoutInterval = 120
        return (request, bodyFile)
    }

    private func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf":
            return "application/pdf"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        case "webp":
            return "image/webp"
        case "bmp":
            return "image/bmp"
        case "tif", "tiff":
            return "image/tiff"
        default:
            return "application/octet-stream"
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
