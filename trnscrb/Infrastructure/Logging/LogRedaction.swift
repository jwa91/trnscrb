import Foundation

enum LogRedaction {
    private static let fallbackSummary: String = "<redacted-url>"

    static func sourceURLSummary(_ url: URL) -> String {
        if url.isFileURL {
            let fileName: String = url.lastPathComponent
            guard !fileName.isEmpty else {
                return fallbackSummary
            }
            return "file://\(fileName)"
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme: String = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host: String = components.host,
              !host.isEmpty else {
            return fallbackSummary
        }

        components.user = nil
        components.password = nil
        components.query = nil
        components.percentEncodedQuery = nil
        components.fragment = nil
        components.percentEncodedFragment = nil

        guard let redactedURL: URL = components.url else {
            return fallbackSummary
        }
        return redactedURL.absoluteString
    }
}
