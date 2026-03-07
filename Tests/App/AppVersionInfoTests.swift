import Foundation
import Testing

@testable import trnscrb

struct AppVersionInfoTests {
    @Test func summaryPrefersBundleMetadataWhenPresent() {
        let summary: String = AppVersionInfo.summary(
            infoDictionary: [
                "CFBundleShortVersionString": "0.3.0",
                "CFBundleVersion": "71"
            ],
            executableURL: URL(fileURLWithPath: "/tmp/trnscrb"),
            currentDirectoryURL: URL(fileURLWithPath: "/tmp")
        )

        #expect(summary == "0.3.0 (71)")
    }

    @Test func summaryFallsBackToRepositoryVersionFile() throws {
        let repositoryURL: URL = FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-version-test-\(UUID().uuidString)")
        let buildURL: URL = repositoryURL.appending(path: ".build/debug")
        try FileManager.default.createDirectory(at: buildURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        try "0.3.0\n".write(
            to: repositoryURL.appending(path: "VERSION"),
            atomically: true,
            encoding: .utf8
        )

        let summary: String = AppVersionInfo.summary(
            infoDictionary: [:],
            executableURL: buildURL.appending(path: "trnscrb"),
            currentDirectoryURL: buildURL
        )

        #expect(summary == "0.3.0")
    }

    @Test func summaryUsesDevelopmentFallbackWhenNoMetadataExists() {
        let summary: String = AppVersionInfo.summary(
            infoDictionary: [:],
            executableURL: URL(fileURLWithPath: "/tmp/trnscrb"),
            currentDirectoryURL: URL(fileURLWithPath: "/tmp")
        )

        #expect(summary == "Development build")
    }
}
