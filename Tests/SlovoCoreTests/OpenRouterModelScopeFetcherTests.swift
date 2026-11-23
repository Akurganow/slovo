import Foundation
import Testing
import SlovoCore

@Suite("OpenRouterModelScopeFetcher (spec rev 3 §4 K7)")
struct OpenRouterModelScopeFetcherTests {
    private struct FixedKey: OpenRouterKeyProvider {
        func apiKey() throws -> String { "sk-test" }
    }
    private struct NoKey: OpenRouterKeyProvider {
        struct Missing: Error {}
        func apiKey() throws -> String { throw Missing() }
    }

    private func fetcher(_ scenario: StubScenario, key: any OpenRouterKeyProvider = FixedKey()) -> OpenRouterModelScopeFetcher {
        OpenRouterModelScopeFetcher(session: scenario.makeSession(), keyProvider: key)
    }

    @Test
    func requestShapeAndHappyPath() async throws {
        let body = Data(#"{"data":[{"id":"a/b"},{"id":"c/d"}]}"#.utf8)
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: body))
        let ids = try await fetcher(scenario).fetchScopeIds()
        #expect(ids == ["a/b", "c/d"])
        let request = scenario.recordedRequests[0].request
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/models/user")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer sk-test")
    }

    @Test
    func non200Throws() async {
        let scenario = StubScenario(response: .http(status: 401, headers: [:], body: Data()))
        await #expect(throws: OpenRouterModelScopeFetcher.ScopeFetchError.apiError(status: 401)) {
            _ = try await fetcher(scenario).fetchScopeIds()
        }
    }

    @Test
    func transportErrorThrowsOffline() async {
        let scenario = StubScenario(response: .transportError(URLError(.notConnectedToInternet)))
        await #expect(throws: OpenRouterModelScopeFetcher.ScopeFetchError.offline) {
            _ = try await fetcher(scenario).fetchScopeIds()
        }
    }

    @Test
    func malformedJsonThrows() async {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Data("not json".utf8)))
        await #expect(throws: OpenRouterModelScopeFetcher.ScopeFetchError.malformedResponse) {
            _ = try await fetcher(scenario).fetchScopeIds()
        }
    }

    @Test
    func missingKeyThrowsWithoutRequest() async {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Data()))
        await #expect(throws: OpenRouterModelScopeFetcher.ScopeFetchError.missingKey) {
            _ = try await fetcher(scenario, key: NoKey()).fetchScopeIds()
        }
        #expect(scenario.recordedRequests.isEmpty)
    }
}
