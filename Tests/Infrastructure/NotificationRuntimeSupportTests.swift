import Foundation
import Testing

@testable import trnscrb

struct NotificationRuntimeSupportTests {
    @Test func reportsNotificationsUnsupportedWhenRunningViaSwiftRun() {
        let bundleURL: URL = URL(filePath: "/Users/jw/developer/trnscrb/.build/arm64-apple-macosx/debug/")

        #expect(
            !NotificationRuntimeSupport.areUserNotificationsSupported(
                bundleURL: bundleURL,
                environment: [:]
            )
        )
    }

    @Test func reportsNotificationsUnsupportedForTestHost() {
        let bundleURL: URL = URL(filePath: "/Applications/trnscrb.app")

        #expect(
            !NotificationRuntimeSupport.areUserNotificationsSupported(
                bundleURL: bundleURL,
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
            )
        )
    }

    @Test func reportsNotificationsSupportedInsideAppBundle() {
        let bundleURL: URL = URL(filePath: "/Applications/trnscrb.app")

        #expect(
            NotificationRuntimeSupport.areUserNotificationsSupported(
                bundleURL: bundleURL,
                environment: [:]
            )
        )
    }
}
