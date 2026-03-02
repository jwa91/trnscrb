import Foundation

@testable import trnscrb

final class MockDeliveryGateway: DeliveryGateway, @unchecked Sendable {
    /// Records delivered results.
    var deliveredResults: [TranscriptionResult] = []
    /// If set, deliver throws this error.
    var deliverError: (any Error)?

    func deliver(result: TranscriptionResult) async throws {
        if let error = deliverError { throw error }
        deliveredResults.append(result)
    }
}
