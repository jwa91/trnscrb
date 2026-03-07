import Foundation

/// Transcribes audio files via the Mistral Voxtral API.
///
/// Endpoint: `POST https://api.mistral.ai/v1/audio/transcriptions`
/// Model: `voxtral-mini-latest`
/// Supports direct local file upload (`file`) or externally reachable URLs (`file_url`).
public struct MistralAudioProvider: TranscriptionGateway {
    /// Mistral audio transcription endpoint URL string.
    private static let endpointString: String = "https://api.mistral.ai/v1/audio/transcriptions"

    /// This provider is selected when mode is Mistral.
    public let providerMode: ProviderMode = .mistral
    /// Mistral can process direct local files and remotely reachable URLs.
    public let supportedSourceKinds: Set<TranscriptionSourceKind> = [.localFile, .remoteURL]

    /// Audio file extensions this provider handles.
    public var supportedExtensions: Set<String> { FileType.audioExtensions }

    /// Gateway for retrieving the Mistral API key.
    private let settingsGateway: any SettingsGateway
    /// URL session for HTTP requests.
    private let urlSession: URLSession
    /// Opens security-scoped file URLs when needed.
    private let fileAccess: any SecurityScopedFileAccessing

    /// Creates an audio transcription provider.
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

    /// Transcribes audio from a local file URL or remote URL and returns the text.
    public func process(sourceURL: URL) async throws -> String {
        let apiKey: String = try await loadAPIKey()
        let requestStartedAt: Date = Date()
        AppLog.network.info("Starting audio transcription request for \(LogRedaction.sourceURLSummary(sourceURL), privacy: .public)")

        let request: URLRequest = try makeRequest(apiKey: apiKey, sourceURL: sourceURL)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MistralError.invalidResponse("Not an HTTP response")
        }
        AppLog.network.info("Audio response HTTP \(http.statusCode, privacy: .public)")
        guard http.statusCode == 200 else {
            let responseBody: String = String(data: data, encoding: .utf8) ?? ""
            throw MistralError.requestFailed(statusCode: http.statusCode, body: responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw MistralError.invalidResponse("Missing 'text' field in response")
        }

        let elapsedMs: Int = Int((Date().timeIntervalSince(requestStartedAt) * 1000).rounded())
        AppLog.network.info("Audio transcription finished in \(elapsedMs, privacy: .public) ms")

        return text
    }

    /// Retrieves the Mistral API key from the Keychain via SettingsGateway.
    private func loadAPIKey() async throws -> String {
        guard let apiKey: String = try await settingsGateway.getSecret(for: .mistralAPIKey)?
            .trimmedCredentialValue,
              !apiKey.isEmpty else {
            throw MistralError.missingAPIKey
        }
        return apiKey
    }

    private func makeRequest(apiKey: String, sourceURL: URL) throws -> URLRequest {
        guard let endpointURL: URL = URL(string: Self.endpointString) else {
            throw MistralError.invalidResponse("Invalid endpoint URL")
        }

        let boundary: String = "Boundary-\(UUID().uuidString)"
        var request: URLRequest = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var fields: [(name: String, value: String)] = [("model", "voxtral-mini-latest")]
        var fileParts: [MultipartFilePart] = []
        if sourceURL.isFileURL {
            let fileData: Data = try loadFileData(fileURL: sourceURL)
            let fileName: String = sourceURL.lastPathComponent.isEmpty
                ? "audio"
                : sourceURL.lastPathComponent
            fileParts.append(
                MultipartFilePart(
                    name: "file",
                    fileName: fileName,
                    mimeType: audioMimeType(for: sourceURL.pathExtension),
                    data: fileData
                )
            )
        } else {
            fields.append(("file_url", sourceURL.absoluteString))
        }

        request.httpBody = multipartBody(boundary: boundary, fields: fields, fileParts: fileParts)
        request.timeoutInterval = 300
        return request
    }

    private func multipartBody(
        boundary: String,
        fields: [(name: String, value: String)],
        fileParts: [MultipartFilePart]
    ) -> Data {
        var data: Data = Data()

        for field in fields {
            data.append("--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            data.append("\(field.value)\r\n")
        }

        for filePart in fileParts {
            data.append("--\(boundary)\r\n")
            data.append(
                "Content-Disposition: form-data; name=\"\(filePart.name)\"; filename=\"\(filePart.fileName)\"\r\n"
            )
            data.append("Content-Type: \(filePart.mimeType)\r\n\r\n")
            data.append(filePart.data)
            data.append("\r\n")
        }

        data.append("--\(boundary)--\r\n")
        return data
    }

    private func loadFileData(fileURL: URL) throws -> Data {
        let startedAccessing: Bool = fileAccess.startAccessing(fileURL)
        defer {
            if startedAccessing {
                fileAccess.stopAccessing(fileURL)
            }
        }
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw MistralError.invalidResponse(
                "Could not read local audio file at \(fileURL.lastPathComponent)."
            )
        }
    }

    private func audioMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/mp4"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        case "ogg":
            return "audio/ogg"
        default:
            return "application/octet-stream"
        }
    }
}

private struct MultipartFilePart {
    let name: String
    let fileName: String
    let mimeType: String
    let data: Data
}

private extension Data {
    mutating func append(_ string: String) {
        self.append(Data(string.utf8))
    }
}
