import Foundation

@testable import trnscrb

actor MockNotificationGateway: NotificationGateway {
    private var notifications: [(title: String, body: String)] = []

    func recordedNotifications() -> [(title: String, body: String)] {
        notifications
    }

    func notify(title: String, body: String) async {
        notifications.append((title: title, body: body))
    }
}
