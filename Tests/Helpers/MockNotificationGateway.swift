import Foundation

@testable import trnscrb

actor MockNotificationGateway: NotificationGateway {
    private var notifications: [(identifier: String, title: String, body: String)] = []

    func recordedNotifications() -> [(identifier: String, title: String, body: String)] {
        notifications
    }

    func notify(identifier: String, title: String, body: String) async {
        notifications.append((identifier: identifier, title: title, body: body))
    }
}
