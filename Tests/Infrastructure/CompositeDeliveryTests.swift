import Foundation
import Testing

@testable import trnscrb

/// Records calls without side effects.
private final class SpyDelivery: DeliveryGateway, @unchecked Sendable {
    var delivered: [TranscriptionResult] = []

    func deliver(result: TranscriptionResult) async throws {
        delivered.append(result)
    }
}

private func makeResult() -> TranscriptionResult {
    TranscriptionResult(markdown: "# Hello", sourceFileName: "test.mp3", sourceFileType: .audio)
}

struct CompositeDeliveryTests {
    @Test func deliversToClipboardWhenEnabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings.copyToClipboard = true
        gateway.settings.saveToFolder = false
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        try await delivery.deliver(result: makeResult())
        #expect(clipboard.delivered.count == 1)
        #expect(file.delivered.count == 0)
    }

    @Test func deliversToFileWhenEnabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings.copyToClipboard = false
        gateway.settings.saveToFolder = true
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        try await delivery.deliver(result: makeResult())
        #expect(clipboard.delivered.count == 0)
        #expect(file.delivered.count == 1)
    }

    @Test func deliversToBothWhenBothEnabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings.copyToClipboard = true
        gateway.settings.saveToFolder = true
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        try await delivery.deliver(result: makeResult())
        #expect(clipboard.delivered.count == 1)
        #expect(file.delivered.count == 1)
    }

    @Test func deliversToNeitherWhenBothDisabled() async throws {
        let clipboard: SpyDelivery = SpyDelivery()
        let file: SpyDelivery = SpyDelivery()
        let gateway: MockSettingsGateway = MockSettingsGateway()
        gateway.settings.copyToClipboard = false
        gateway.settings.saveToFolder = false
        let delivery: CompositeDelivery = CompositeDelivery(
            clipboard: clipboard, file: file, settingsGateway: gateway
        )
        try await delivery.deliver(result: makeResult())
        #expect(clipboard.delivered.count == 0)
        #expect(file.delivered.count == 0)
    }
}
