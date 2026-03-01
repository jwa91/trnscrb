import Foundation

/// Per-session request handler for isolated test mocking.
final class MockRequestHandler: @unchecked Sendable {
    /// Handler that receives the request and returns a response + data.
    var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
}

/// Intercepts URLSession requests for testing. Each session gets its own handler
/// via `makeMockURLSession()`, so test suites can run in parallel safely.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// Header key used to route requests to their session-specific handler.
    private static let sessionIDHeader: String = "X-Mock-Session-ID"

    /// Lock protecting the `handlers` dictionary from concurrent mutation.
    private static let lock: NSLock = NSLock()

    /// Per-session handlers, keyed by session ID.
    nonisolated(unsafe) private static var handlers: [String: MockRequestHandler] = [:]

    /// Registers a handler for the given session ID.
    static func register(_ mock: MockRequestHandler, for sessionID: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers[sessionID] = mock
    }

    /// Looks up the handler for the given session ID.
    private static func mock(for sessionID: String) -> MockRequestHandler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[sessionID]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let sessionID = request.value(forHTTPHeaderField: Self.sessionIDHeader),
              let mock = Self.mock(for: sessionID),
              let handler = mock.handler else {
            let id: String = request.value(forHTTPHeaderField: Self.sessionIDHeader) ?? "nil"
            fatalError("MockURLProtocol: no handler for session \(id)")
        }
        do {
            // URLSession moves httpBody to httpBodyStream when using URLProtocol.
            // Reconstruct the body so test handlers can access request.httpBody directly.
            var mutableRequest: URLRequest = request
            if mutableRequest.httpBody == nil, let stream = mutableRequest.httpBodyStream {
                mutableRequest.httpBody = Self.readStream(stream)
            }
            let (response, data) = try handler(mutableRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    /// Reads all bytes from an InputStream into Data.
    private static func readStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data: Data = Data()
        let bufferSize: Int = 1024
        let buffer: UnsafeMutablePointer<UInt8> = .allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let bytesRead: Int = stream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return data
    }

    override func stopLoading() {}
}

/// Creates a URLSession that routes all requests through MockURLProtocol.
///
/// Each session gets an isolated handler, so test suites running in parallel
/// do not interfere with each other. Set `mock.handler` before making requests.
func makeMockURLSession() -> (session: URLSession, mock: MockRequestHandler) {
    let sessionID: String = UUID().uuidString
    let mock: MockRequestHandler = MockRequestHandler()
    MockURLProtocol.register(mock, for: sessionID)
    let config: URLSessionConfiguration = .ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    config.httpAdditionalHeaders = ["X-Mock-Session-ID": sessionID]
    return (URLSession(configuration: config), mock)
}
