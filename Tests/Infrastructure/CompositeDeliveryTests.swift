import Foundation
import Testing

@testable import trnscrb

/// Records calls without side effects.
private actor SpyDelivery: DeliveryGateway {
    private var delivered: [TranscriptionResult] = []
    private let report: DeliveryReport

    init(report: DeliveryReport = DeliveryReport()) {
        self.report = report
    }

    func deliver(result: TranscriptionResult) async throws -> DeliveryReport {
        delivered.append(result)
        return report
    }

    func deliveredCount() -> Int {
        delivered.count
    }
}

private func makeResult() -> TranscriptionResult {
    TranscriptionResult(markdown: "# Hello", sourceFileName: "test.mp3", sourceFileType: .audio)
}

private enum CompositeDeliveryTestError: Error, Sendable {
    case failedDestination
}

struct CompositeDeliveryTests {
    @Test func deliversToClipboardWhenEnabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: true, saveToFolder: false)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        let report: DeliveryReport = try await delivery.deliver(result: makeResult())
        #expect(await clipboard.deliveredCount() == 1)
        #expect(await file.deliveredCount() == 0)
        #expect(report.warnings.isEmpty)
    }

    @Test func deliversToFileWhenEnabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: false, saveToFolder: true)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        let report: DeliveryReport = try await delivery.deliver(result: makeResult())
        #expect(await clipboard.deliveredCount() == 0)
        #expect(await file.deliveredCount() == 1)
        #expect(report.warnings.isEmpty)
    }

    @Test func deliversToBothWhenBothEnabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: true, saveToFolder: true)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        let report: DeliveryReport = try await delivery.deliver(result: makeResult())
        #expect(await clipboard.deliveredCount() == 1)
        #expect(await file.deliveredCount() == 1)
        #expect(report.warnings.isEmpty)
    }

    @Test func fallsBackToClipboardWhenBothOutputsAreDisabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: false, saveToFolder: false)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        let report: DeliveryReport = try await delivery.deliver(result: makeResult())
        #expect(await clipboard.deliveredCount() == 1)
        #expect(await file.deliveredCount() == 0)
        #expect(report.warnings.isEmpty)
    }

    @Test func succeedsWhenClipboardSucceedsAndFileSaveFails() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: MockDeliveryGateway = MockDeliveryGateway(
            deliverError: CompositeDeliveryTestError.failedDestination
        )
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: true, saveToFolder: true)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )

        let report: DeliveryReport = try await delivery.deliver(result: makeResult())

        #expect(await clipboard.deliveredCount() == 1)
        #expect(await file.recordedDeliveredResults().isEmpty)
        #expect(report.warnings == ["Copied markdown to the clipboard, but saving the file failed."])
    }

    @Test func succeedsWhenFileSaveSucceedsAndClipboardFails() async throws {
        let clipboard: MockDeliveryGateway = MockDeliveryGateway(
            deliverError: CompositeDeliveryTestError.failedDestination
        )
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: true, saveToFolder: true)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )

        let report: DeliveryReport = try await delivery.deliver(result: makeResult())

        #expect(await clipboard.recordedDeliveredResults().isEmpty)
        #expect(await file.deliveredCount() == 1)
        #expect(report.warnings == ["Saved markdown to the output folder, but copying to the clipboard failed."])
    }

    @Test func returnsSavedFileURLFromFileDelivery() async throws {
        let savedFileURL: URL = URL(filePath: "/tmp/output.md")
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery(
            report: DeliveryReport(savedFileURL: savedFileURL)
        )
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: true, saveToFolder: true)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )

        let report: DeliveryReport = try await delivery.deliver(result: makeResult())

        #expect(report.savedFileURL == savedFileURL)
    }
}
