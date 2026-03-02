import Foundation

/// The delivery-layer outcome after attempting to surface markdown to the user.
public struct DeliveryReport: Sendable, Equatable {
    /// Non-fatal warnings for destinations that failed after at least one succeeded.
    public let warnings: [String]

    public init(warnings: [String] = []) {
        self.warnings = warnings
    }

    public static let success: DeliveryReport = DeliveryReport()
}
