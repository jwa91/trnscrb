import Foundation

@testable import trnscrb

actor MockDeliveryGateway: DeliveryGateway {
    /// Records delivered results.
    private var deliveredResults: [TranscriptionResult]
    /// If set, deliver throws this error.
    private var deliverError: (any Error & Sendable)?
    /// Optional warnings returned after a successful delivery.
    private var deliverWarnings: [String]

    init(
        deliverError: (any Error & Sendable)? = nil,
        deliverWarnings: [String] = []
    ) {
        self.deliverError = deliverError
        self.deliverWarnings = deliverWarnings
        self.deliveredResults = []
    }

    func setDeliverError(_ error: (any Error & Sendable)?) {
        deliverError = error
    }

    func recordedDeliveredResults() -> [TranscriptionResult] {
        deliveredResults
    }

    func deliver(result: TranscriptionResult) async throws -> DeliveryReport {
        if let deliverError {
            throw deliverError
        }
        deliveredResults.append(result)
        return DeliveryReport(warnings: deliverWarnings)
    }
}
