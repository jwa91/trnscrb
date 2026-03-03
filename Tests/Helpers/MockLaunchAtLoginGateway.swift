import Foundation

@testable import trnscrb

actor MockLaunchAtLoginGateway: LaunchAtLoginGateway {
    private var callCount: Int = 0
    private var appliedValues: [Bool] = []

    func recordedCallCount() -> Int {
        callCount
    }

    func recordedAppliedValues() -> [Bool] {
        appliedValues
    }

    func apply(enabled: Bool) async throws {
        callCount += 1
        appliedValues.append(enabled)
    }
}
