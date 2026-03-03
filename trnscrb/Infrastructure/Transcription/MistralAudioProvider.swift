import Foundation

/// Transcribes audio files via the Mistral Voxtral API.
///
/// Endpoint: `POST https://api.mistral.ai/v1/audio/transcriptions`
/// Model: `voxtral-mini-latest`
/// Accepts a presigned S3 URL via the `file_url` JSON field.
public struct MistralAudioProvider: TranscriptionGateway {
    /// Mistral audio transcription endpoint URL string.
    private static let endpointString: String = "https://api.mistral.ai/v1/audio/transcriptions"

    /// This provider is selected when mode is Mistral.
    public let providerMode: ProviderMode = .mistral
    /// Mistral expects a remotely reachable URL.
    public let sourceKind: TranscriptionSourceKind = .remoteURL

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
        AppLog.network.info("Starting audio transcription for \(sourceURL.absoluteString, privacy: .public)")

        guard let endpointURL: URL = URL(string: Self.endpointString) else {
            throw MistralError.invalidResponse("Invalid endpoint URL")
        }
        let body: [String: Any] = [
            "model": "voxtral-mini-latest",
            "file_url": sourceURL.absoluteString
        ]
        var request: URLRequest = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300

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
}
