import Foundation

/// Abstracts local user notifications triggered by job lifecycle events.
public protocol NotificationGateway: Sendable {
    /// Requests permission if needed and posts a local user notification.
    func notify(identifier: String, title: String, body: String) async
}
