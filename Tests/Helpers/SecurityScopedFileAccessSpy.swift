import Foundation

@testable import trnscrb

final class SecurityScopedFileAccessSpy: SecurityScopedFileAccessing, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private let startResult: Bool
    private var startedURLs: [URL] = []
    private var stoppedURLs: [URL] = []

    init(startResult: Bool = true) {
        self.startResult = startResult
    }

    func startAccessing(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        startedURLs.append(url)
        return startResult
    }

    func stopAccessing(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        stoppedURLs.append(url)
    }

    func recordedStartedURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return startedURLs
    }

    func recordedStoppedURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return stoppedURLs
    }
}
