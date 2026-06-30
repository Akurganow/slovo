import Foundation
import Testing

import LoquiCore
import LoquiTestSupport

// Epic 06 — AC-8 (SECURITY-CRITICAL, the load-bearing anti-false-green): the
// 5-channel redaction sentinel sweep. A UNIQUE high-entropy SYNTHETIC sentinel
// is injected into EACH of the 5 cloud-cleanup channels; running a full
// `AnthropicCleaner.clean` per channel, NONE may reach the `RedactionSafeLog`
// sink.
//
// Contract under test (the Cleaner files must keep every payload OUT of the log;
// CURRENTLY the WRONG-ON-PURPOSE `_RedScaffold_Cleaner.swift` stub LOGS the raw
// 4xx error body → the channel-B sentinel reaches the sink → RED).
//
// THE SENSITIVITY (per-channel, not per-variable): a transcript-only check would
// MISS the 4xx-body leak. The per-channel sweep is what catches the headline
// trap `log.event("…\(error.responseBody)")`.
//
// SECURITY/P1: sentinels are SYNTHETIC high-entropy strings — no real key, no
// seed terms, no organization/private term/private contact content.
@Suite("Epic 06 AC-8 redaction sentinel sweep")
struct RedactionSentinelTests {
    // Each channel's sentinel is unique so a leak names the exact channel.
    private static let sentinelTranscript = "S3NT1NEL-TRANSCRIPT-7a1f9c2e-DO-NOT-LOG"
    private static let sentinelCleaned = "S3NT1NEL-CLEANED-4b8d6e0a-DO-NOT-LOG"
    private static let sentinelVocab = "S3NT1NEL-VOCAB-2c9f5a3b-DO-NOT-LOG"
    private static let sentinelBody = "S3NT1NEL-ERRORBODY-9e4c1d7f-DO-NOT-LOG"
    private static let sentinelKey = "S3NT1NEL-APIKEY-6f2a8b4c-DO-NOT-LOG"

    // Computed (not stored) so it is not a non-Sendable mutable global under Swift 6.
    private static var config: CleanupConfig { CleanupConfig(writingStyle: .formal, language: .auto) }

    /// Runs a full `clean` with a capturing log sink and the given stub state +
    /// inputs, returning every line the cleaner emitted to the log.
    private static func capturedLogLines(
        keyOutcome: FakeKeyProvider.Outcome,
        stub: StubResponse,
        raw: String,
        vocab: [Term]
    ) async -> [String] {
        let scenario = StubScenario(response: stub)
        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "loqui", category: "cleaner-test") { captured.append($0) }
        let cleaner = AnthropicCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeKeyProvider(keyOutcome),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 8),
            log: log
        )
        _ = try? await cleaner.clean(raw, config: config, context: PersonalizationContext(vocabulary: vocab))
        return captured
    }

    private static func successBody(text: String) -> StubResponse {
        let json = """
        {"content":[{"type":"text","text":"\(text)"}],"stop_reason":"end_turn"}
        """
        return .http(status: 200, headers: [:], body: Data(json.utf8))
    }

    private static func assertNoLeak(_ lines: [String], _ sentinel: String, channel: String) {
        let joined = lines.joined(separator: "\n")
        #expect(!joined.contains(sentinel),
                "REDACTION LEAK on the \(channel) channel: a sentinel reached the log sink:\n\(joined)")
    }

    /// Channel 1 — transcript: logging the raw input.
    @Test
    func transcriptNeverReachesLog() async {
        let lines = await Self.capturedLogLines(
            keyOutcome: .success("synthetic-key"),
            stub: Self.successBody(text: "cleaned"),
            raw: Self.sentinelTranscript, vocab: []
        )
        Self.assertNoLeak(lines, Self.sentinelTranscript, channel: "transcript")
    }

    /// Channel 2 — cleaned output: logging the result.
    @Test
    func cleanedOutputNeverReachesLog() async {
        let lines = await Self.capturedLogLines(
            keyOutcome: .success("synthetic-key"),
            stub: Self.successBody(text: Self.sentinelCleaned),
            raw: "raw", vocab: []
        )
        Self.assertNoLeak(lines, Self.sentinelCleaned, channel: "cleaned-output")
    }

    /// Channel 3 — vocabulary term in the prompt: logging the prompt body.
    @Test
    func vocabularyTermNeverReachesLog() async {
        let vocab = [Term(term: Self.sentinelVocab, expansion: nil, lang: .en, weight: 9)]
        let lines = await Self.capturedLogLines(
            keyOutcome: .success("synthetic-key"),
            stub: Self.successBody(text: "cleaned"),
            raw: "raw", vocab: vocab
        )
        Self.assertNoLeak(lines, Self.sentinelVocab, channel: "vocabulary-term")
    }

    /// Channel 4 — 4xx response body: THE HEADLINE TRAP `log(error.responseBody)`.
    /// Stated sensitivity: a transcript-only check would MISS this; the per-channel
    /// sweep catches it. (The scaffold logs the 4xx body → RED here.)
    @Test
    func errorResponseBodyNeverReachesLog() async {
        let body = Data(#"{"type":"error","error":{"message":"\#(Self.sentinelBody)"}}"#.utf8)
        let lines = await Self.capturedLogLines(
            keyOutcome: .success("synthetic-key"),
            stub: .http(status: 400, headers: [:], body: body),
            raw: "raw", vocab: []
        )
        Self.assertNoLeak(lines, Self.sentinelBody, channel: "4xx-error-body")
    }

    /// Channel 5 — API key: logging the key / putting it in an error.
    @Test
    func apiKeyNeverReachesLog() async {
        let lines = await Self.capturedLogLines(
            keyOutcome: .success(Self.sentinelKey),
            stub: Self.successBody(text: "cleaned"),
            raw: "raw", vocab: []
        )
        Self.assertNoLeak(lines, Self.sentinelKey, channel: "api-key")
    }
}
