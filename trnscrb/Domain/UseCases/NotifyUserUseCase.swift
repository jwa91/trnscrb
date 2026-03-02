import Foundation

/// Posts user-visible notifications for important app events.
public struct NotifyUserUseCase: Sendable {
    private let gateway: any NotificationGateway

    public init(gateway: any NotificationGateway) {
        self.gateway = gateway
    }

    public func notify(title: String, body: String) async {
        await gateway.notify(title: title, body: body)
    }
}
