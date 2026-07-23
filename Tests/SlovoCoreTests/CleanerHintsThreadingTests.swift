import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

@Suite("Cleaner hint threading")
struct CleanerHintsThreadingTests {
    private static var config: CleanupConfig {
        CleanupConfig(model: "openai/gpt-5.6-luna", writingStyle: .casual, language: .auto)
    }

    private static var context: PersonalizationContext {
        PersonalizationContext(vocabulary: [])
    }

    private static let hints = CleanupHints(
        inputLocale: "ru",
        spellFindings: [SpellFinding(token: "prieved", guesses: ["prived", "primed"])]
    )

    /// Stated sensitivity: an OpenRouter cleaner that ignores `hints` (does not pass
    /// them to `buildPrompt`) sends a system message with no advisory block, so the
    /// locale and token never reach the request body — this turns red.
    @Test
    func openRouterCleanerPutsHintsInTheRequestBody() async throws {
        let scenario = StubScenario(response: .http(
            status: 200,
            headers: [:],
            body: Data(#"{"choices":[{"message":{"role":"assistant","content":"cleaned"}}]}"#.utf8)
        ))
        let cleaner = OpenRouterCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeOpenRouterKeyProvider(.success("synthetic-openrouter-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        _ = try await cleaner.clean("raw", config: Self.config, context: Self.context, hints: Self.hints)

        try #require(scenario.recordedRequests.count == 1)
        let (_, body) = scenario.recordedRequests[0]
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: String]])
        let systemContent = try #require(messages.first?["content"])
        #expect(systemContent.contains("Keyboard input language at dictation time: Russian (ru)."))
        #expect(systemContent.contains("prieved → prived, primed"))
    }

    /// Stated sensitivity: a FallbackCleaner that forwards to the chain's 3-arg
    /// `clean` (dropping hints) makes the recorded hints empty — this turns red.
    @Test
    func fallbackCleanerForwardsHintsDownTheChain() async throws {
        let recording = FakeCleaner(outcome: .success("HI"))
        let fallback = FallbackCleaner(chain: [recording, PassThrough()], statusReporter: { _ in })

        _ = try await fallback.clean("raw", config: Self.config, context: Self.context, hints: Self.hints)

        #expect(recording.calls.last?.hints == Self.hints,
                "the fallback chain must forward hints unchanged; got \(String(describing: recording.calls.last?.hints))")
    }
}
