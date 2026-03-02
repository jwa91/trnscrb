import Foundation

/// Applies the saved launch-at-login preference through a domain-owned gateway.
public struct ApplyLaunchAtLoginUseCase: Sendable {
    private let gateway: any LaunchAtLoginGateway

    public init(gateway: any LaunchAtLoginGateway) {
        self.gateway = gateway
    }

    public func apply(enabled: Bool) async throws {
        try await gateway.apply(enabled: enabled)
    }
}
