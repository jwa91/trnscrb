import Foundation
import Testing

@testable import trnscrb

private actor ControlledCleanupOperation {
    private var runCount: Int = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func run() async {
        runCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func recordedRunCount() -> Int {
        runCount
    }

    func resumeNextRun() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

@Suite(.serialized)
@MainActor
struct RetentionCleanupCoordinatorTests {
    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let clock: ContinuousClock = ContinuousClock()
        let deadline: ContinuousClock.Instant = clock.now + timeout
        while !(await condition()) {
            if clock.now >= deadline {
                return false
            }
            await Task.yield()
        }
        return true
    }

    @Test func triggerBlocksOverlapAndAllowsLaterRuns() async {
        let coordinator: RetentionCleanupCoordinator = RetentionCleanupCoordinator()
        let operation: ControlledCleanupOperation = ControlledCleanupOperation()

        coordinator.trigger {
            await operation.run()
        }

        let firstStarted: Bool = await waitUntil {
            await operation.recordedRunCount() == 1
        }
        #expect(firstStarted)

        coordinator.trigger {
            await operation.run()
        }

        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(await operation.recordedRunCount() == 1)

        await operation.resumeNextRun()

        let firstFinished: Bool = await waitUntil {
            !coordinator.isRunning
        }
        #expect(firstFinished)

        coordinator.trigger {
            await operation.run()
        }

        let secondStarted: Bool = await waitUntil {
            await operation.recordedRunCount() == 2
        }
        #expect(secondStarted)

        await operation.resumeNextRun()
    }
}
