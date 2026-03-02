import Foundation

/// Abstracts applying the app's launch-at-login setting to the host system.
public protocol LaunchAtLoginGateway: Sendable {
    /// Applies the requested launch-at-login state.
    func apply(enabled: Bool) async throws
}
