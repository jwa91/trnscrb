import Foundation

enum AppVersionInfo {
    static func summary(
        bundle: Bundle = .main,
        executableURL: URL = URL(fileURLWithPath: CommandLine.arguments[0]),
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> String {
        summary(
            infoDictionary: bundle.infoDictionary ?? [:],
            executableURL: executableURL,
            currentDirectoryURL: currentDirectoryURL
        )
    }

    static func summary(
        infoDictionary: [String: Any],
        executableURL: URL,
        currentDirectoryURL: URL
    ) -> String {
        let shortVersion: String = versionString(
            forInfoDictionaryKey: "CFBundleShortVersionString",
            in: infoDictionary
        ) ?? repositoryVersion(
            searchingFrom: executableURL
        ) ?? repositoryVersion(
            searchingFrom: currentDirectoryURL
        ) ?? "Development build"

        guard let buildNumber: String = versionString(
            forInfoDictionaryKey: "CFBundleVersion",
            in: infoDictionary
        ) else {
            return shortVersion
        }

        return "\(shortVersion) (\(buildNumber))"
    }

    private static func versionString(
        forInfoDictionaryKey key: String,
        in infoDictionary: [String: Any]
    ) -> String? {
        guard let raw: String = infoDictionary[key] as? String else {
            return nil
        }
        let trimmed: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$") else {
            return nil
        }
        return trimmed
    }

    private static func repositoryVersion(searchingFrom startURL: URL) -> String? {
        let fileManager: FileManager = .default
        let standardizedStartURL: URL = startURL.standardizedFileURL
        let baseURL: URL = fileManager.fileExists(atPath: standardizedStartURL.path)
            ? standardizedStartURL
            : standardizedStartURL.deletingLastPathComponent()

        for candidateDirectory in ancestorDirectories(of: baseURL) {
            let versionFileURL: URL = candidateDirectory.appending(path: "VERSION")
            guard fileManager.fileExists(atPath: versionFileURL.path) else {
                continue
            }
            guard let rawVersion: String = try? String(contentsOf: versionFileURL, encoding: .utf8) else {
                continue
            }
            let trimmedVersion: String = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedVersion.isEmpty {
                return trimmedVersion
            }
        }

        return nil
    }

    private static func ancestorDirectories(of startURL: URL) -> [URL] {
        var directories: [URL] = []
        var currentURL: URL = startURL.hasDirectoryPath ? startURL : startURL.deletingLastPathComponent()

        while true {
            directories.append(currentURL)
            let parentURL: URL = currentURL.deletingLastPathComponent()
            if parentURL.path == currentURL.path {
                break
            }
            currentURL = parentURL
        }

        return directories
    }
}
