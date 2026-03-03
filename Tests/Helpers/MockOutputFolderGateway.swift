import Foundation

@testable import trnscrb

final class MockOutputFolderGateway: @unchecked Sendable, OutputFolderGateway {
    private let lock: NSLock = NSLock()
    private var preparedURL: URL
    private var error: (any Error & Sendable)?
    private var preparedPaths: [String] = []

    init(preparedURL: URL = FileManager.default.temporaryDirectory.appending(path: "trnscrb-output")) {
        self.preparedURL = preparedURL
    }

    func setPreparedURL(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        preparedURL = url
    }

    func setError(_ error: (any Error & Sendable)?) {
        lock.lock()
        defer { lock.unlock() }
        self.error = error
    }

    func recordedPreparedPaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return preparedPaths
    }

    func prepareOutputFolder(path: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        preparedPaths.append(path)
        if let error {
            throw error
        }
        return preparedURL
    }
}
