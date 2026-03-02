import AppKit
import Foundation
import Testing

@testable import trnscrb

private func makeResult(
    markdown: String = "# Test",
    fileName: String = "recording.mp3"
) -> TranscriptionResult {
    TranscriptionResult(markdown: markdown, sourceFileName: fileName, sourceFileType: .audio)
}

// MARK: - ClipboardDelivery

@Suite(.serialized)
@MainActor
struct ClipboardDeliveryTests {
    @Test func deliverCopiesMarkdownToClipboard() async throws {
        let delivery: ClipboardDelivery = ClipboardDelivery()
        let result: TranscriptionResult = makeResult(markdown: "# Hello World")
        _ = try await delivery.deliver(result: result)

        let clipboard: String? = NSPasteboard.general.string(forType: .string)
        #expect(clipboard == "# Hello World")
    }

    @Test func deliverOverwritesPreviousClipboard() async throws {
        let delivery: ClipboardDelivery = ClipboardDelivery()
        _ = try await delivery.deliver(result: makeResult(markdown: "first"))
        _ = try await delivery.deliver(result: makeResult(markdown: "second"))

        let clipboard: String? = NSPasteboard.general.string(forType: .string)
        #expect(clipboard == "second")
    }
}

// MARK: - FileDelivery

struct FileDeliveryTests {
    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "trnscrb-test-\(UUID().uuidString)")
    }

    private func makeDelivery(saveFolderPath: String) -> (FileDelivery, MockSettingsGateway) {
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(saveFolderPath: saveFolderPath)
        )
        let delivery: FileDelivery = FileDelivery(settingsGateway: gateway)
        return (delivery, gateway)
    }

    @Test func deliverCreatesMarkdownFile() async throws {
        let tempDir: URL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let (delivery, _) = makeDelivery(saveFolderPath: tempDir.path())

        _ = try await delivery.deliver(result: makeResult(markdown: "# Notes", fileName: "meeting.mp3"))

        let fileURL: URL = tempDir.appending(path: "meeting.md")
        let content: String = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content == "# Notes")
    }

    @Test func deliverCreatesFolderIfMissing() async throws {
        let tempDir: URL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let (delivery, _) = makeDelivery(saveFolderPath: tempDir.path())

        #expect(!FileManager.default.fileExists(atPath: tempDir.path()))
        _ = try await delivery.deliver(result: makeResult())
        #expect(FileManager.default.fileExists(atPath: tempDir.path()))
    }

    @Test func deliverAppendsSuffixWhenFileExists() async throws {
        let tempDir: URL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let (delivery, _) = makeDelivery(saveFolderPath: tempDir.path())

        // First delivery — creates recording.md
        _ = try await delivery.deliver(result: makeResult(markdown: "first", fileName: "recording.mp3"))
        // Second delivery — should create recording-TIMESTAMP.md
        _ = try await delivery.deliver(result: makeResult(markdown: "second", fileName: "recording.mp3"))

        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: tempDir.path())
        #expect(files.count == 2)
        #expect(files.contains("recording.md"))
        #expect(files.contains(where: { $0.hasPrefix("recording-") && $0.hasSuffix(".md") }))
    }

    @Test func deliverGeneratesUniqueNamesForRepeatedCollisions() async throws {
        let tempDir: URL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let (delivery, _) = makeDelivery(saveFolderPath: tempDir.path())

        _ = try await delivery.deliver(result: makeResult(markdown: "first", fileName: "recording.mp3"))
        _ = try await delivery.deliver(result: makeResult(markdown: "second", fileName: "recording.mp3"))
        _ = try await delivery.deliver(result: makeResult(markdown: "third", fileName: "recording.mp3"))

        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: tempDir.path())
        let recordingFiles: [String] = files.filter { $0.hasPrefix("recording") && $0.hasSuffix(".md") }

        #expect(recordingFiles.count == 3)
        #expect(Set(recordingFiles).count == 3)
    }

    @Test func deliverStripsOriginalExtension() async throws {
        let tempDir: URL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let (delivery, _) = makeDelivery(saveFolderPath: tempDir.path())

        _ = try await delivery.deliver(result: makeResult(fileName: "scan.pdf"))

        let files: [String] = try FileManager.default.contentsOfDirectory(atPath: tempDir.path())
        #expect(files == ["scan.md"])
    }
}
