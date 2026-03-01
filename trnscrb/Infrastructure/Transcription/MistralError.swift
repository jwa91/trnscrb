import Foundation

/// Errors from Mistral API calls (audio transcription and OCR).
public enum MistralError: Error, Sendable, Equatable {
    /// The Mistral API key is not configured in the Keychain.
    case missingAPIKey
    /// The API returned a non-200 status code.
    case requestFailed(statusCode: Int, body: String)
    /// The API response could not be parsed.
    case invalidResponse(String)
}
