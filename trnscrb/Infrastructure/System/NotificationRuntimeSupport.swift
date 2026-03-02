import Foundation

enum NotificationRuntimeSupport {
    static func areUserNotificationsSupported(
        bundleURL: URL = Bundle.main.bundleURL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }

        return bundleURL.pathComponents.contains { component in
            component.hasSuffix(".app")
        }
    }
}
