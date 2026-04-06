import Foundation

public protocol SecurityScopedFileAccessing: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

public struct NoOpSecurityScopedFileAccess: SecurityScopedFileAccessing {
    public init() {}

    public func startAccessing(_ url: URL) -> Bool {
        false
    }

    public func stopAccessing(_ url: URL) {}
}
