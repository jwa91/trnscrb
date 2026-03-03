import Foundation

/// Processes PDFs and images via the Mistral OCR API.
///
/// Endpoint: `POST https://api.mistral.ai/v1/ocr`
/// Model: `mistral-ocr-latest`
/// PDFs use `DocumentURLChunk` (`type: "document_url"`).
/// Images use `ImageURLChunk` (`type: "image_url"`).
/// Response pages' markdown is concatenated with double newlines.
public struct MistralOCRProvider: TranscriptionGateway {
    // swiftlint:disable:next force_unwrapping
    private static let endpoint: URL = URL(string: "https://api.mistral.ai/v1/ocr")!
    /// This provider is selected when mode is Mistral.
    public let providerMode: ProviderMode = .mistral
    /// Mistral expects a remotely reachable URL.
    public let sourceKind: TranscriptionSourceKind = .remoteURL

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
        AppLog.network.info("Starting OCR request for \(sourceURL.absoluteString, privacy: .public)")

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

        return try parsePages(data)
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
