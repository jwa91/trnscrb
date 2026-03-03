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

extension MistralError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Configure your Mistral API key in settings."
        case .requestFailed(let statusCode, let body):
            switch statusCode {
            case 401:
                return "Mistral rejected the API key."
            case 403:
                return "Mistral denied access for this API key."
            case 429:
                return "Mistral rate-limited the request."
            default:
                let trimmedBody: String = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedBody.isEmpty
                    ? "Mistral request failed with HTTP \(statusCode)."
                    : "Mistral request failed with HTTP \(statusCode): \(trimmedBody)"
            }
        case .invalidResponse(let message):
            return "Invalid response from Mistral: \(message)"
        }
    }
}
