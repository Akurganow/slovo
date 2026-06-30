import Foundation
import Synchronization
import Testing

import SlovoCore
import SlovoTestSupport

@Suite("Cleanup provider OpenAI cleaner")
struct OpenAICleanerTests {
    private static let sentinelTranscript = "S3NT1NEL-OPENAI-TRANSCRIPT-72d8-DO-NOT-LOG"
    private static let sentinelCleaned = "S3NT1NEL-OPENAI-CLEANED-49bc-DO-NOT-LOG"
    private static let sentinelVocab = "S3NT1NEL-OPENAI-VOCAB-18af-DO-NOT-LOG"
    private static let sentinelBody = "S3NT1NEL-OPENAI-BODY-65de-DO-NOT-LOG"
    private static let sentinelKey = "S3NT1NEL-OPENAI-KEY-90c1-DO-NOT-LOG"

    private static var config: CleanupConfig {
        CleanupConfig(model: "gpt-5.4-mini", writingStyle: .casual, language: .auto)
    }

    private static var context: PersonalizationContext {
        PersonalizationContext(vocabulary: [])
    }

    private static func successBody(text: String) -> Data {
        Data(
            """
            {"output":[{"content":[{"type":"output_text","text":"\(text)"}]}]}
            """.utf8
        )
    }

    /// Stated sensitivity: use Chat Completions, omit `instructions`, omit
    /// `store=false`, or hard-code the model -> the recorded request shape fails.
    @Test
    func outboundRequestUsesResponsesShapeAndConfiguredModel() async throws {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned")))
        let cleaner = OpenAICleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenAIKeyProvider(.success("synthetic-openai-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        _ = try await cleaner.clean("raw transcript", config: Self.config, context: Self.context)

        try #require(scenario.recordedRequests.count == 1, "exactly one request expected")
        let (request, body) = scenario.recordedRequests[0]
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer synthetic-openai-key")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "gpt-5.4-mini")
        #expect(json?["input"] as? String == "raw transcript")
        #expect(json?["store"] as? Bool == false,
                "cleanup calls must not ask the provider to retain responses")
        #expect(json?["temperature"] as? Double == 0,
                "cleanup requests must use deterministic decoding")
        let instructions = json?["instructions"] as? String
        #expect(instructions?.contains("Return only the cleaned transcript") == true)
    }

    /// Stated sensitivity: parse only an SDK-only `output_text` convenience field
    /// or the first top-level item instead of content text -> this returns empty.
    @Test
    func success200ReturnsOutputTextContent() async throws {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned prose")))
        let cleaner = OpenAICleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenAIKeyProvider(.success("synthetic-openai-key")),
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
        let cleaner = OpenAICleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenAIKeyProvider(.success("synthetic-openai-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        _ = try? await cleaner.clean("raw transcript", config: Self.config, context: Self.context)

        #expect(scenario.recordedRequests.count == 1,
                "fail-closed: exactly one outbound POST, got \(scenario.recordedRequests.count)")
    }

    /// Stated sensitivity: map 429 to generic apiError -> the `.rateLimited`
    /// match fails and the fallback chain cannot distinguish throttling.
    @Test
    func http429MapsToRateLimited() async {
        let scenario = StubScenario(response: .http(status: 429, headers: ["retry-after": "5"], body: Data()))
        let cleaner = OpenAICleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenAIKeyProvider(.success("synthetic-openai-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        await Self.expectThrows(cleaner) { error in
            guard case .rateLimited = error else { return "expected .rateLimited, got \(error)" }
            return nil
        }
    }

    /// Stated sensitivity: remove the provider cache -> two cleanup calls invoke
    /// the secret reader twice and can trigger repeated Keychain prompts.
    @Test
    func openAIKeyProviderCachesSecretAcrossCleanupCalls() async throws {
        let reads = Mutex<Int>(0)
        let keyProvider = KeychainOpenAIKeyProvider(
            readKey: {
                reads.withLock { $0 += 1 }
                return "synthetic-openai-key"
            },
            keyExists: { true },
            writeKey: { _ in }
        )
        let first = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "one")))
        let second = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "two")))

        _ = try await OpenAICleaner(
            session: first.makeSession(),
            keyProvider: keyProvider,
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        ).clean("raw one", config: Self.config, context: Self.context)
        _ = try await OpenAICleaner(
            session: second.makeSession(),
            keyProvider: keyProvider,
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        ).clean("raw two", config: Self.config, context: Self.context)

        #expect(reads.withLock { $0 } == 1,
                "one process-scoped OpenAI key provider must read the Keychain secret once")
    }

    /// Stated sensitivity: log the OpenAI request body, response body, output, or
    /// bearer key -> the matching synthetic sentinel reaches the capturing sink.
    @Test
    func openAIPayloadChannelsNeverReachLog() async {
        let body = Data(#"{"error":{"message":"\#(Self.sentinelBody)"}}"#.utf8)
        let cases: [(String, FakeOpenAIKeyProvider.Outcome, StubResponse, String, [Term])] = [
            (
                "transcript",
                .success("synthetic-openai-key"),
                .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned")),
                Self.sentinelTranscript,
                []
            ),
            (
                "cleaned-output",
                .success("synthetic-openai-key"),
                .http(status: 200, headers: [:], body: Self.successBody(text: Self.sentinelCleaned)),
                "raw",
                []
            ),
            (
                "vocabulary",
                .success("synthetic-openai-key"),
                .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned")),
                "raw",
                [Term(term: Self.sentinelVocab, expansion: nil, lang: .en, weight: 9)]
            ),
            (
                "error-body",
                .success("synthetic-openai-key"),
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
            for sentinel in [Self.sentinelTranscript, Self.sentinelCleaned, Self.sentinelVocab, Self.sentinelBody, Self.sentinelKey] {
                #expect(!joined.contains(sentinel),
                        "REDACTION LEAK on OpenAI \(channel): sentinel reached log sink:\n\(joined)")
            }
        }
    }

    private static func capturedLogLines(
        keyOutcome: FakeOpenAIKeyProvider.Outcome,
        stub: StubResponse,
        raw: String,
        vocabulary: [Term]
    ) async -> [String] {
        let scenario = StubScenario(response: stub)
        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "slovo", category: "openai-cleaner-test") { captured.append($0) }
        let cleaner = OpenAICleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenAIKeyProvider(keyOutcome),
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
        _ cleaner: OpenAICleaner,
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
