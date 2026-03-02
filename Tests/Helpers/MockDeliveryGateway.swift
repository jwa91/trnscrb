import Foundation

@testable import trnscrb

actor MockDeliveryGateway: DeliveryGateway {
    /// Records delivered results.
    private var deliveredResults: [TranscriptionResult]
    /// If set, deliver throws this error.
    private var deliverError: (any Error & Sendable)?

    init(deliverError: (any Error & Sendable)? = nil) {
        self.deliverError = deliverError
        self.deliveredResults = []
    }

    func setDeliverError(_ error: (any Error & Sendable)?) {
        deliverError = error
    }

    func recordedDeliveredResults() -> [TranscriptionResult] {
        deliveredResults
    }

    func deliver(result: TranscriptionResult) async throws {
        if let deliverError {
            throw deliverError
        }
        deliveredResults.append(result)
    }
}
