import Foundation
import UserNotifications

/// macOS local notification implementation used for job success/failure messages.
public struct UserNotificationClient: NotificationGateway {
    public init() {}

    public func notify(title: String, body: String) async {
        guard !isTestHost else { return }

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
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }

    private var isTestHost: Bool {
        let bundlePath: String = Bundle.main.bundleURL.path
        return bundlePath.contains("/swift/pm")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
