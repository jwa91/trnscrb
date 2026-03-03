import Foundation

/// Errors raised while probing external service connectivity.
public enum ConnectivityError: Error, Sendable {
    case invalidEndpointURL
    case invalidURLComponents
    case invalidMistralURL
    case nonHTTPResponse
    case invalidAPIKey
    case requestFailed(statusCode: Int)
}

extension ConnectivityError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidEndpointURL:
            return "Invalid endpoint URL"
        case .invalidURLComponents:
            return "Invalid URL components"
        case .invalidMistralURL:
            return "Invalid URL"
        case .nonHTTPResponse:
            return "Not an HTTP response"
        case .invalidAPIKey:
            return "Invalid API key"
        case .requestFailed(let statusCode):
            return "HTTP \(statusCode)"
        }
    }
}

/// Infrastructure implementation for settings connectivity checks.
public struct ConnectivityClient: ConnectivityGateway {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func testS3(settings: AppSettings, s3SecretKey: String) async throws {
        let normalizedSettings: AppSettings = settings.normalizedForUse
        let normalizedS3SecretKey: String = s3SecretKey.trimmedCredentialValue

        let signer: S3Signer = S3Signer(
            accessKey: normalizedSettings.s3AccessKey,
            secretKey: normalizedS3SecretKey,
            region: normalizedSettings.s3Region
        )

        guard let bucketURL = URL(string: normalizedSettings.s3EndpointURL)?
            .appendingPathComponent(normalizedSettings.s3BucketName, isDirectory: false) as URL? else {
            throw ConnectivityError.invalidEndpointURL
        }
        guard var components = URLComponents(
            url: bucketURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw ConnectivityError.invalidURLComponents
        }

        components.queryItems = [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "max-keys", value: "0")
        ]

        guard let listURL = components.url else {
            throw ConnectivityError.invalidURLComponents
        }

        var request: URLRequest = URLRequest(url: listURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        signer.sign(&request, payloadHash: S3Signer.unsignedPayload)

        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectivityError.nonHTTPResponse
        }
        guard http.statusCode == 200 else {
            throw ConnectivityError.requestFailed(statusCode: http.statusCode)
        }
    }

    public func testMistral(apiKey: String) async throws {
        let normalizedAPIKey: String = apiKey.trimmedCredentialValue
        guard let url = URL(string: "https://api.mistral.ai/v1/models") else {
            throw ConnectivityError.invalidMistralURL
        }

        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(normalizedAPIKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConnectivityError.nonHTTPResponse
        }
        if http.statusCode == 200 {
            return
        }
        if http.statusCode == 401 {
            throw ConnectivityError.invalidAPIKey
        }
        throw ConnectivityError.requestFailed(statusCode: http.statusCode)
    }
}
