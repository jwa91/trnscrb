import Foundation

@testable import trnscrb

final class MockOutputFolderGateway: @unchecked Sendable, OutputFolderGateway {
    private let lock: NSLock = NSLock()
    private var preparedURL: URL
    private var error: (any Error & Sendable)?
    private var preparedPaths: [String] = []
    private var refreshedBookmarkBase64: String?
    private var stopAccessCount: Int = 0

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

    func setRefreshedBookmarkBase64(_ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        refreshedBookmarkBase64 = value
    }

    func recordedPreparedPaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return preparedPaths
    }

    func recordedStopAccessCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return stopAccessCount
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

    func prepareOutputFolder(settings: AppSettings) throws -> PreparedOutputFolder {
        lock.lock()
        preparedPaths.append(settings.saveFolderPath)
        let preparedURL: URL = preparedURL
        let error: (any Error & Sendable)? = error
        let refreshedBookmarkBase64: String? = refreshedBookmarkBase64
        lock.unlock()

        if let error {
            throw error
        }

        return PreparedOutputFolder(
            url: preparedURL,
            refreshedBookmarkBase64: refreshedBookmarkBase64,
            stopAccessingHandler: { [weak self] in
                self?.lock.lock()
                self?.stopAccessCount += 1
                self?.lock.unlock()
            }
        )
    }
}
