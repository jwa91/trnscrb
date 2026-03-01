import Foundation

/// Abstracts delivery of transcription results to the user.
///
/// Concrete implementations: clipboard copy, file save, or both.
public protocol DeliveryGateway: Sendable {
    /// Delivers a transcription result to the user.
    /// - Parameter result: The completed transcription result.
    func deliver(result: TranscriptionResult) async throws
}
