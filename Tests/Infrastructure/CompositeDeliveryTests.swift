import Foundation
import Testing

@testable import trnscrb

private func makeResult() -> TranscriptionResult {
    TranscriptionResult(markdown: "# Hello", sourceFileName: "test.mp3", sourceFileType: .audio)
}

private enum CompositeDeliveryTestError: Error, Sendable {
    case failedDestination
}

struct CompositeDeliveryTests {
    @Test func alwaysDeliversToFile() async throws {
        let clipboard: MockDeliveryGateway = MockDeliveryGateway()
        let file: MockDeliveryGateway = MockDeliveryGateway()
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: false)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        let report: DeliveryReport = try await delivery.deliver(result: makeResult())
        #expect(await clipboard.recordedDeliveredResults().isEmpty)
        #expect(await file.recordedDeliveredResults().count == 1)
        #expect(report.warnings.isEmpty)
    }

    @Test func deliversToClipboardAndFileWhenClipboardEnabled() async throws {
        let clipboard: MockDeliveryGateway = MockDeliveryGateway()
        let file: MockDeliveryGateway = MockDeliveryGateway()
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: true)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        let report: DeliveryReport = try await delivery.deliver(result: makeResult())
        #expect(await clipboard.recordedDeliveredResults().count == 1)
        #expect(await file.recordedDeliveredResults().count == 1)
        #expect(report.warnings.isEmpty)
    }

    @Test func fileFailureIsFatalEvenWhenClipboardSucceeds() async {
        let clipboard: MockDeliveryGateway = MockDeliveryGateway()
        let file: MockDeliveryGateway = MockDeliveryGateway(
            deliverError: CompositeDeliveryTestError.failedDestination
        )
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: true)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )

        await #expect(throws: CompositeDeliveryTestError.self) {
            _ = try await delivery.deliver(result: makeResult())
        }
        #expect(await clipboard.recordedDeliveredResults().isEmpty)
    }

    @Test func succeedsWhenFileSaveSucceedsAndClipboardFails() async throws {
        let clipboard: MockDeliveryGateway = MockDeliveryGateway(
            deliverError: CompositeDeliveryTestError.failedDestination
        )
        let file: MockDeliveryGateway = MockDeliveryGateway()
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: true)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )

        let report: DeliveryReport = try await delivery.deliver(result: makeResult())

        #expect(await clipboard.recordedDeliveredResults().isEmpty)
        #expect(await file.recordedDeliveredResults().count == 1)
        #expect(report.warnings == ["Saved markdown to the output folder, but copying to the clipboard failed."])
    }

    @Test func returnsSavedFileURLFromFileDelivery() async throws {
        let savedFileURL: URL = URL(filePath: "/tmp/output.md")
        let clipboard: MockDeliveryGateway = MockDeliveryGateway()
        let file: MockDeliveryGateway = MockDeliveryGateway(
            savedFileURL: savedFileURL
        )
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: true)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )

        let report: DeliveryReport = try await delivery.deliver(result: makeResult())

        #expect(report.savedFileURL == savedFileURL)
    }
}
