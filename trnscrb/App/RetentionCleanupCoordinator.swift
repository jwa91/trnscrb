import Foundation

@MainActor
final class RetentionCleanupCoordinator {
    private var currentTask: Task<Void, Never>?

    var isRunning: Bool {
        currentTask != nil
    }

    func trigger(operation: @escaping @Sendable () async -> Void) {
        guard currentTask == nil else { return }
        currentTask = Task { @MainActor [weak self] in
            defer {
                self?.currentTask = nil
            }
            await operation()
        }
    }
}
