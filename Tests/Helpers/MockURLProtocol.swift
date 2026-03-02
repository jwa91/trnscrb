import Foundation

/// Per-session request handler for isolated test mocking.
final class MockRequestHandler {
    private let lock: NSLock = NSLock()
    /// Handler that receives the request and returns a response + data.
    private var _handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _handler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _handler = newValue
        }
    }
}

/// Intercepts URLSession requests for testing. Each session gets its own handler
/// via `makeMockURLSession()`, so test suites can run in parallel safely.
final class MockURLProtocol: URLProtocol {
    /// Header key used to route requests to their session-specific handler.
    private static let sessionIDHeader: String = "X-Mock-Session-ID"
    private static let registry: MockURLProtocolRegistry = MockURLProtocolRegistry()

    /// Registers a handler for the given session ID.
    static func register(_ mock: MockRequestHandler, for sessionID: String) {
        registry.register(mock, for: sessionID)
    }

    static func unregister(for sessionID: String) {
        registry.unregister(for: sessionID)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let sessionID = request.value(forHTTPHeaderField: Self.sessionIDHeader),
              let mock = Self.registry.mock(for: sessionID),
              let handler = mock.handler else {
            let id: String = request.value(forHTTPHeaderField: Self.sessionIDHeader) ?? "nil"
            client?.urlProtocol(
                self,
                didFailWithError: MockURLProtocolError.missingHandler(sessionID: id)
            )
            return
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

private final class MockURLProtocolRegistry: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var handlers: [String: MockRequestHandler] = [:]

    func register(_ mock: MockRequestHandler, for sessionID: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers[sessionID] = mock
    }

    func unregister(for sessionID: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers[sessionID] = nil
    }

    func mock(for sessionID: String) -> MockRequestHandler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[sessionID]
    }
}

enum MockURLProtocolError: Error, Equatable {
    case missingHandler(sessionID: String)
}

/// Creates a URLSession that routes all requests through MockURLProtocol.
///
/// Each session gets an isolated handler, so test suites running in parallel
/// do not interfere with each other. Set `mock.handler` before making requests.
func makeMockURLSession() -> (sessionID: String, session: URLSession, mock: MockRequestHandler) {
    let sessionID: String = UUID().uuidString
    let mock: MockRequestHandler = MockRequestHandler()
    MockURLProtocol.register(mock, for: sessionID)
    let config: URLSessionConfiguration = .ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    config.httpAdditionalHeaders = ["X-Mock-Session-ID": sessionID]
    return (sessionID, URLSession(configuration: config), mock)
}
