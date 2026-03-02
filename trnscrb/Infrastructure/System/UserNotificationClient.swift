import Foundation
import UserNotifications

/// macOS local notification implementation used for job success/failure messages.
public struct UserNotificationClient: NotificationGateway {
    public init() {}

    public func notify(identifier: String, title: String, body: String) async {
        guard NotificationRuntimeSupport.areUserNotificationsSupported() else { return }

        let center: UNUserNotificationCenter = .current()
        let authorizationStatus: UNAuthorizationStatus = await notificationAuthorizationStatus(
            center: center
        )

        switch authorizationStatus {
        case .notDetermined:
            let granted: Bool = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
        case .authorized, .provisional, .ephemeral:
            break
        case .denied:
            return
        @unknown default:
            return
        }

        let content: UNMutableNotificationContent = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request: UNNotificationRequest = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }
    private func notificationAuthorizationStatus(center: UNUserNotificationCenter) async
        -> UNAuthorizationStatus
    {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
}
