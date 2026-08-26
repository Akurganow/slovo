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

    @Test func requestShapeAndHappyPath() async throws {
        let body = Data(#"{"data":[{"id":"a/b"},{"id":"c/d"}]}"#.utf8)
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: body))
        let ids = try await fetcher(scenario).fetchScopeIds()
        #expect(ids == ["a/b", "c/d"])
        let request = scenario.recordedRequests[0].request
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/models/user")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer sk-test")
    }

    @Test func non200Throws() async {
        let scenario = StubScenario(response: .http(status: 401, headers: [:], body: Data()))
        await #expect(throws: OpenRouterModelScopeFetcher.ScopeFetchError.self) {
            _ = try await fetcher(scenario).fetchScopeIds()
        }
    }

    @Test func transportErrorThrowsOffline() async {
        let scenario = StubScenario(response: .transportError(URLError(.notConnectedToInternet)))
        await #expect(throws: OpenRouterModelScopeFetcher.ScopeFetchError.self) {
            _ = try await fetcher(scenario).fetchScopeIds()
        }
    }

    @Test func malformedJsonThrows() async {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Data("not json".utf8)))
        await #expect(throws: OpenRouterModelScopeFetcher.ScopeFetchError.self) {
            _ = try await fetcher(scenario).fetchScopeIds()
        }
    }

    @Test func missingKeyThrowsWithoutRequest() async {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Data()))
        await #expect(throws: OpenRouterModelScopeFetcher.ScopeFetchError.self) {
            _ = try await fetcher(scenario, key: NoKey()).fetchScopeIds()
        }
        #expect(scenario.recordedRequests.isEmpty)
    }
}

@Suite("Scope fetcher source guards (spec K7 positive anchor, D4)")
struct ScopeFetcherSourceGuardTests {
    private static func source(_ repoRelative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(repoRelative), encoding: .utf8)
    }

    // K7 positive anchor: EVERY log call is one of the five pinned redaction-safe
    // events (count enforced — five sites, five distinct strings), and no log
    // line interpolates the response.
    // Sensitivity (demonstrated once, then reverted): add
    // `log.event("body: \(data)")` → both the count and interpolation pins go RED.
    @Test func fetcherLogsExactlyThePinnedEvents() throws {
        let fetcher = try Self.source("Sources/SlovoCore/Cleaner/OpenRouterModelScopeFetcher.swift")
        #expect(fetcher.components(separatedBy: "log.event(").count - 1 == 5)
        #expect(fetcher.contains(#"log.event("scope fetched n=\(ids.count)")"#))
        #expect(fetcher.contains(#"log.event("scope fetch failed: missingKey")"#))
        #expect(fetcher.contains(#"log.event("scope fetch failed: offline")"#))
        #expect(fetcher.contains(#"log.event("scope fetch failed: apiError")"#))
        #expect(fetcher.contains(#"log.event("scope fetch failed: malformed")"#))
        #expect(!fetcher.contains("\\(data"))
        #expect(!fetcher.contains("\\(decoded"))
        #expect(!fetcher.contains("\\(entries"))
        #expect(!fetcher.contains("String(data:"))
    }

    // D4: the scope layer persists nothing. Sensitivity: add a UserDefaults write
    // to either file → RED.
    @Test func scopeLayerPersistsNothing() throws {
        for file in ["Sources/SlovoCore/Cleaner/OpenRouterModelScopeFetcher.swift",
                     "Sources/SlovoCore/Cleaner/CleanupScopeReducer.swift"] {
            let source = try Self.source(file)
            #expect(!source.contains("UserDefaults"))
            #expect(!source.contains("FileManager"))
        }
    }
}
