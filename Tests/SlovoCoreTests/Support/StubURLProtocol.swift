import Foundation

// TEMPORARY RED-SCAFFOLD SUPPORT — the implementer KEEPS this (test-only, never
// shipped). Records every outbound request and
// returns a programmable canned response or a transport `URLError`.
//
// Per-test ISOLATION (so Swift Testing's parallel runner cannot interleave two
// tests' programmed responses / request counts): each test creates its own
// `StubScenario` (a fresh recorder + canned response) and registers it in a
// lock-guarded registry keyed by a UUID. The session's requests carry that UUID
// in a header, so the protocol dispatches to the right per-test scenario. No
// cross-test shared mutable response state.

/// A canned outcome for a stubbed request.
enum StubResponse {
    case http(status: Int, headers: [String: String], body: Data)
    case transportError(URLError)
}

/// One test's isolated stub state: the response it returns + the requests it saw.
final class StubScenario: @unchecked Sendable {
    let id = UUID().uuidString
    private let lock = NSLock()
    private var _response: StubResponse
    private var _recorded: [(request: URLRequest, body: Data)] = []

    init(response: StubResponse) { self._response = response }

    var response: StubResponse {
        get { lock.lock(); defer { lock.unlock() }; return _response }
        set { lock.lock(); defer { lock.unlock() }; _response = newValue }
    }
    var recordedRequests: [(request: URLRequest, body: Data)] {
        lock.lock(); defer { lock.unlock() }; return _recorded
    }
    fileprivate func record(_ request: URLRequest, body: Data) {
        lock.lock(); defer { lock.unlock() }; _recorded.append((request, body))
    }

    /// A session whose only protocol is the stub, tagged so requests route here.
    func makeSession() -> URLSession {
        StubURLProtocol.register(self)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [StubURLProtocol.scenarioHeader: id]
        return URLSession(configuration: config)
    }
}

final class StubURLProtocol: URLProtocol {
    static let scenarioHeader = "X-Slovo-Stub-Scenario"

    // Lock-guarded registry of live scenarios, keyed by id.
    nonisolated(unsafe) private static var scenarios: [String: StubScenario] = [:]
    private static let registryLock = NSLock()

    static func register(_ scenario: StubScenario) {
        registryLock.lock(); defer { registryLock.unlock() }
        scenarios[scenario.id] = scenario
    }
    /// Removes a scenario from the registry once its request has completed, so the
    /// process-global dict does not grow unboundedly across a test run. The test
    /// still holds its own `StubScenario` reference (for `recordedRequests`); this
    /// only drops the registry entry.
    private static func unregister(_ id: String) {
        registryLock.lock(); defer { registryLock.unlock() }
        scenarios[id] = nil
    }
    private static func scenario(for request: URLRequest) -> StubScenario? {
        guard let id = request.value(forHTTPHeaderField: scenarioHeader) else { return nil }
        registryLock.lock(); defer { registryLock.unlock() }
        return scenarios[id]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let scenario = Self.scenario(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        // Self-clean: drop the registry entry once this request is served.
        defer { Self.unregister(scenario.id) }
        scenario.record(request, body: Self.bodyData(from: request))

        switch scenario.response {
        case .http(let status, let headers, let data):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .transportError(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
