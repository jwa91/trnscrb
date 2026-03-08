import Foundation

public protocol SecurityScopedFileAccessing: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

public struct SecurityScopedFileAccess: SecurityScopedFileAccessing {
    public init() {}

    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
