import Foundation
import Testing

@testable import trnscrb

/// Records calls without side effects.
private actor SpyDelivery: DeliveryGateway {
    private var delivered: [TranscriptionResult] = []

    func deliver(result: TranscriptionResult) async throws {
        delivered.append(result)
    }

    func deliveredCount() -> Int {
        delivered.count
    }
}

private func makeResult() -> TranscriptionResult {
    TranscriptionResult(markdown: "# Hello", sourceFileName: "test.mp3", sourceFileType: .audio)
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
        try await delivery.deliver(result: makeResult())
        #expect(await clipboard.deliveredCount() == 1)
        #expect(await file.deliveredCount() == 0)
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
        try await delivery.deliver(result: makeResult())
        #expect(await clipboard.deliveredCount() == 0)
        #expect(await file.deliveredCount() == 1)
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
        try await delivery.deliver(result: makeResult())
        #expect(await clipboard.deliveredCount() == 1)
        #expect(await file.deliveredCount() == 1)
    }

    @Test func deliversToNeitherWhenBothDisabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway(
            settings: AppSettings(copyToClipboard: false, saveToFolder: false)
        )
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        try await delivery.deliver(result: makeResult())
        #expect(await clipboard.deliveredCount() == 0)
        #expect(await file.deliveredCount() == 0)
    }
}
