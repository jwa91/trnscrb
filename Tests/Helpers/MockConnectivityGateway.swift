import Foundation

@testable import trnscrb

actor MockConnectivityGateway: ConnectivityGateway {
    private var s3Error: (any Error & Sendable)?
    private var mistralError: (any Error & Sendable)?
    private var s3CallCount: Int = 0
    private var mistralCallCount: Int = 0

    func setS3Error(_ error: (any Error & Sendable)?) {
        s3Error = error
    }

    func setMistralError(_ error: (any Error & Sendable)?) {
        mistralError = error
    }

    func recordedS3CallCount() -> Int {
        s3CallCount
    }

    func recordedMistralCallCount() -> Int {
        mistralCallCount
    }

    func testS3(settings _: AppSettings, s3SecretKey _: String) async throws {
        s3CallCount += 1
        if let s3Error {
            throw s3Error
        }
    }

    func testMistral(apiKey _: String) async throws {
        mistralCallCount += 1
        if let mistralError {
            throw mistralError
        }
    }
}
