import Foundation
import Testing

@testable import trnscrb

struct OutputFileNameFormatterTests {
    @Test func fileNameUsesConfiguredTemplateVariables() {
        let date: Date = Date(timeIntervalSince1970: 1_762_424_130)
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let expectedTimestamp: String = formatter.string(from: date)

        let settings: AppSettings = AppSettings(
            outputFileNamePrefix: "notes-",
            outputFileNameTemplate: "{prefix}{fileType}-{timestamp}"
        )

        let fileName: String = OutputFileNameFormatter.fileName(
            sourceFileName: "meeting-note.m4a",
            fileType: .audio,
            settings: settings,
            date: date
        )

        #expect(fileName == "notes-audio-\(expectedTimestamp).md")
    }

    @Test func fileNameStripsExplicitMarkdownExtensionFromTemplateOutput() {
        let settings: AppSettings = AppSettings(
            outputFileNameTemplate: "{originalFilename}.md"
        )

        let fileName: String = OutputFileNameFormatter.fileName(
            sourceFileName: "scan.pdf",
            fileType: .pdf,
            settings: settings
        )

        #expect(fileName == "scan.md")
    }
}
