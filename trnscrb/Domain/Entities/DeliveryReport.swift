import Foundation

/// The delivery-layer outcome after attempting to surface markdown to the user.
public struct DeliveryReport: Sendable, Equatable {
    /// Non-fatal warnings for destinations that failed after at least one succeeded.
    public let warnings: [String]
    /// Local file URL when delivery saved markdown to disk.
    public let savedFileURL: URL?

    public init(warnings: [String] = [], savedFileURL: URL? = nil) {
        self.warnings = warnings
        self.savedFileURL = savedFileURL
    }
}
