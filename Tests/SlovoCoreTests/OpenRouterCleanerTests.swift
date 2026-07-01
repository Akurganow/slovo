import Foundation
import Synchronization
import Testing

import SlovoCore
import SlovoTestSupport

@Suite("Cleanup provider OpenRouter cleaner")
struct OpenRouterCleanerTests {
    private static let sentinelTranscript = "S3NT1NEL-OPENROUTER-TRANSCRIPT-2d2b-DO-NOT-LOG"
    private static let sentinelCleaned = "S3NT1NEL-OPENROUTER-CLEANED-59fe-DO-NOT-LOG"
    private static let sentinelVocab = "S3NT1NEL-OPENROUTER-VOCAB-bd04-DO-NOT-LOG"
    private static let sentinelBody = "S3NT1NEL-OPENROUTER-BODY-d09b-DO-NOT-LOG"
    private static let sentinelKey = "S3NT1NEL-OPENROUTER-KEY-18e7-DO-NOT-LOG"

    private static var config: CleanupConfig {
        CleanupConfig(model: "openai/gpt-5.4-nano", writingStyle: .casual, language: .auto)
    }

    private static var context: PersonalizationContext {
        PersonalizationContext(vocabulary: [])
    }

    private static func successBody(text: String) -> Data {
        Data(
            """
            {"choices":[{"message":{"role":"assistant","content":"\(text)"}}]}
            """.utf8
        )
    }

    /// Stated sensitivity: using the old OpenAI Responses endpoint/body, omitting
    /// the configured routed model, or sending an unauthenticated request makes
    /// the recorded request-shape assertions go RED.
    @Test
    func outboundRequestUsesOpenRouterChatCompletionsShapeAndConfiguredModel() async throws {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned")))
        let cleaner = OpenRouterCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenRouterKeyProvider(.success("synthetic-openrouter-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        _ = try await cleaner.clean("raw transcript", config: Self.config, context: Self.context)

        try #require(scenario.recordedRequests.count == 1, "exactly one request expected")
        let (request, body) = scenario.recordedRequests[0]
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer synthetic-openrouter-key")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://github.com/slovo-app/slovo")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Slovo")
        #expect(request.timeoutInterval == 30)

        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "openai/gpt-5.4-nano")
        #expect(json["temperature"] as? Double == 0)
        #expect(json["max_tokens"] as? Int == 1_024)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.map(\.["role"]) == ["system", "user"])
        #expect(messages.first?["content"]?.contains("Return only the cleaned transcript") == true)
        #expect(messages.last?["content"] == "raw transcript")
    }

    /// Stated sensitivity: parsing only OpenAI Responses API `output_text`, or
    /// reading the wrong Chat Completions field, returns no cleaned text.
    @Test
    func success200ReturnsAssistantMessageContent() async throws {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned prose")))
        let cleaner = OpenRouterCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenRouterKeyProvider(.success("synthetic-openrouter-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        let output = try await cleaner.clean("raw", config: Self.config, context: Self.context)

        #expect(output == "cleaned prose")
    }

    /// Stated sensitivity: add a retry loop on transport failure -> the transcript
    /// is sent more than once and the request count assertion fails.
    @Test
    func failClosedSendsExactlyOneRequest() async {
        let scenario = StubScenario(response: .transportError(URLError(.timedOut)))
        let cleaner = OpenRouterCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenRouterKeyProvider(.success("synthetic-openrouter-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        _ = try? await cleaner.clean("raw transcript", config: Self.config, context: Self.context)

        #expect(scenario.recordedRequests.count == 1,
                "fail-closed: exactly one outbound POST, got \(scenario.recordedRequests.count)")
    }

    /// Stated sensitivity: mapping 429 to generic apiError makes the fallback
    /// chain lose throttling information.
    @Test
    func http429MapsToRateLimited() async {
        let scenario = StubScenario(response: .http(status: 429, headers: ["retry-after": "5"], body: Data()))
        let cleaner = OpenRouterCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenRouterKeyProvider(.success("synthetic-openrouter-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        await Self.expectThrows(cleaner) { error in
            guard case .rateLimited(let retryAfter) = error else { return "expected .rateLimited, got \(error)" }
            guard retryAfter == 5 else { return "expected retry-after 5, got \(String(describing: retryAfter))" }
            return nil
        }
    }

    /// Stated sensitivity: letting a raw DecodingError escape on malformed 2xx
    /// bypasses `FallbackCleaner`'s CleanupError degradation path.
    @Test
    func malformed200MapsToCleanupError() async {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Data("{}".utf8)))
        let cleaner = OpenRouterCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenRouterKeyProvider(.success("synthetic-openrouter-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        await Self.expectThrows(cleaner) { error in
            guard case .apiError(status: 200) = error else { return "expected .apiError(status: 200), got \(error)" }
            return nil
        }
    }

    /// Stated sensitivity: a key-sourcing error must not become offline/apiError
    /// or carry the key value into the thrown error.
    @Test
    func keySourcingFailureMapsToMissingKey() async {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "ok")))
        let cleaner = OpenRouterCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenRouterKeyProvider(.failure(.missingKey)),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        await Self.expectThrows(cleaner) { error in
            guard case .missingKey = error else { return "expected .missingKey, got \(error)" }
            return nil
        }
    }

    /// Stated sensitivity: remove the provider cache -> two cleanup calls invoke
    /// the secret reader twice and can trigger repeated Keychain prompts.
    @Test
    func openRouterKeyProviderCachesSecretAcrossCleanupCalls() async throws {
        let reads = Mutex<Int>(0)
        let keyProvider = KeychainOpenRouterKeyProvider(
            readKey: {
                reads.withLock { $0 += 1 }
                return "synthetic-openrouter-key"
            },
            keyExists: { true },
            writeKey: { _ in }
        )
        let first = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "one")))
        let second = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "two")))

        _ = try await OpenRouterCleaner(
            session: first.makeSession(),
            keyProvider: keyProvider,
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        ).clean("raw one", config: Self.config, context: Self.context)
        _ = try await OpenRouterCleaner(
            session: second.makeSession(),
            keyProvider: keyProvider,
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        ).clean("raw two", config: Self.config, context: Self.context)

        #expect(reads.withLock { $0 } == 1,
                "one process-scoped OpenRouter key provider must read the Keychain secret once")
    }

    /// Stated sensitivity: logging the request body, response body, output, or
    /// bearer key makes the matching synthetic sentinel reach the capturing sink.
    @Test
    func openRouterPayloadChannelsNeverReachLog() async {
        let body = Data(#"{"error":{"message":"\#(Self.sentinelBody)"}}"#.utf8)
        let cases: [(String, FakeOpenRouterKeyProvider.Outcome, StubResponse, String, [Term])] = [
            (
                "transcript",
                .success("synthetic-openrouter-key"),
                .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned")),
                Self.sentinelTranscript,
                []
            ),
            (
                "cleaned-output",
                .success("synthetic-openrouter-key"),
                .http(status: 200, headers: [:], body: Self.successBody(text: Self.sentinelCleaned)),
                "raw",
                []
            ),
            (
                "vocabulary",
                .success("synthetic-openrouter-key"),
                .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned")),
                "raw",
                [Term(term: Self.sentinelVocab, expansion: nil, lang: .en, weight: 9)]
            ),
            (
                "error-body",
                .success("synthetic-openrouter-key"),
                .http(status: 400, headers: [:], body: body),
                "raw",
                []
            ),
            (
                "api-key",
                .success(Self.sentinelKey),
                .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned")),
                "raw",
                []
            ),
        ]

        for (channel, keyOutcome, stub, raw, vocabulary) in cases {
            let lines = await Self.capturedLogLines(
                keyOutcome: keyOutcome,
                stub: stub,
                raw: raw,
                vocabulary: vocabulary
            )
            let joined = lines.joined(separator: "\n")
            #expect(!lines.isEmpty, "OpenRouter \(channel) must emit coarse logs so this redaction guard is non-vacuous")
            for sentinel in [Self.sentinelTranscript, Self.sentinelCleaned, Self.sentinelVocab, Self.sentinelBody, Self.sentinelKey] {
                #expect(!joined.contains(sentinel),
                        "REDACTION LEAK on OpenRouter \(channel): sentinel reached log sink:\n\(joined)")
            }
        }
    }

    private static func capturedLogLines(
        keyOutcome: FakeOpenRouterKeyProvider.Outcome,
        stub: StubResponse,
        raw: String,
        vocabulary: [Term]
    ) async -> [String] {
        let scenario = StubScenario(response: stub)
        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "slovo", category: "openrouter-cleaner-test") { captured.append($0) }
        let cleaner = OpenRouterCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenRouterKeyProvider(keyOutcome),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 8),
            log: log
        )
        _ = try? await cleaner.clean(
            raw,
            config: Self.config,
            context: PersonalizationContext(vocabulary: vocabulary)
        )
        return captured
    }

    private static func expectThrows(
        _ cleaner: OpenRouterCleaner,
        _ check: (CleanupError) -> String?
    ) async {
        do {
            _ = try await cleaner.clean("raw", config: config, context: context)
            #expect(Bool(false), "expected clean to throw a CleanupError")
        } catch let error as CleanupError {
            if let message = check(error) { #expect(Bool(false), Comment(rawValue: message)) }
        } catch {
            #expect(Bool(false), "expected a CleanupError, got \(error)")
        }
    }
}
