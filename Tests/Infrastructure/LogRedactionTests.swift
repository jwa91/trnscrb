import Foundation
import Testing

@testable import trnscrb

struct LogRedactionTests {
    @Test func sourceURLSummaryRemovesQueryAndFragmentForHTTPURLs() throws {
        let sourceURL: URL = try #require(
            URL(string: "https://s3.example.com/bucket/file.mp3?X-Amz-Signature=abc&X-Amz-Credential=foo#section")
        )

        let summary: String = LogRedaction.sourceURLSummary(sourceURL)

        #expect(summary == "https://s3.example.com/bucket/file.mp3")
        #expect(!summary.contains("?"))
        #expect(!summary.contains("X-Amz-"))
        #expect(!summary.contains("#"))
    }

    @Test func sourceURLSummaryPreservesHostAndPathForHTTPURLs() throws {
        let sourceURL: URL = try #require(
            URL(string: "https://api.example.com/v1/transcribe/audio.mp3?token=secret")
        )

        let summary: String = LogRedaction.sourceURLSummary(sourceURL)

        #expect(summary == "https://api.example.com/v1/transcribe/audio.mp3")
    }

    @Test func sourceURLSummaryRedactsLocalFilePath() {
        let sourceURL: URL = URL(fileURLWithPath: "/Users/jane/Documents/private/meeting.mp3")

        let summary: String = LogRedaction.sourceURLSummary(sourceURL)

        #expect(summary == "file://meeting.mp3")
        #expect(!summary.contains("/Users/jane/Documents/private"))
    }

    @Test func sourceURLSummaryReturnsFallbackForUnsupportedSchemes() throws {
        let sourceURL: URL = try #require(URL(string: "mailto:someone@example.com"))

        let summary: String = LogRedaction.sourceURLSummary(sourceURL)

        #expect(summary == "<redacted-url>")
    }

    @Test func sourceURLSummaryRemovesUserInfoForHTTPURLs() throws {
        let sourceURL: URL = try #require(
            URL(string: "https://alice:secret@s3.example.com/bucket/file.mp3?token=abc")
        )

        let summary: String = LogRedaction.sourceURLSummary(sourceURL)

        #expect(summary == "https://s3.example.com/bucket/file.mp3")
        #expect(!summary.contains("alice"))
        #expect(!summary.contains("secret"))
    }
}
