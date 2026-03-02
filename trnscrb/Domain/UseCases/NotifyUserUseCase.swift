import Foundation

/// Posts user-visible notifications for important app events.
public struct NotifyUserUseCase: Sendable {
    private let gateway: any NotificationGateway

    public init(gateway: any NotificationGateway) {
        self.gateway = gateway
    }

    public func notify(
        title: String,
        body: String,
        identifier: String = UUID().uuidString
    ) async {
        await gateway.notify(identifier: identifier, title: title, body: body)
    }
}
