import Foundation
import Synchronization
import Testing

import SlovoCore
import SlovoTestSupport

// Epic 06 — AC-5 (status→typed-error mapping + parsed text), AC-6 (outbound
// request shape ties to the §18.6 pins), AC-7 (fail-closed: exactly one POST).
//
// Contract under test (implementer builds `Sources/SlovoCore/Cleaner/AnthropicCleaner.swift`
// + codables per plan §1/§6/§7; CURRENTLY the WRONG-ON-PURPOSE
// `_RedScaffold_Cleaner.swift` stub maps 429→.apiError, reads content[0], and
// re-POSTs 3× on transport error → RED).
//
// Each test uses its OWN `StubScenario` (isolated recorder + response), so the
// parallel runner cannot interleave responses/counts. FIXTURE ANCHOR RULE (P1):
// synthetic placeholder text only — no real key, no seed terms.
@Suite("Epic 06 AC-5/AC-6/AC-7 AnthropicCleaner")
struct AnthropicCleanerTests {
    private static var config: CleanupConfig { CleanupConfig(writingStyle: .formal, language: .auto) }
    private static var context: PersonalizationContext { PersonalizationContext(vocabulary: []) }

    private static func cleaner(for scenario: StubScenario) -> AnthropicCleaner {
        AnthropicCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeKeyProvider(.success("synthetic-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )
    }

    private static func successBody(text: String) -> Data {
        // content[0] is a NON-text block, the text block is at index 1, so a
        // `content[0]` reader (the mutation) misses it while `first{type=="text"}`
        // finds it. stop_reason "end_turn" (not refusal).
        Data(#"{"content":[{"type":"thinking","text":null},{"type":"text","text":"\#(text)"}],"stop_reason":"end_turn"}"#.utf8)
    }

    private static func refusalBody() -> Data {
        // Refusal: empty content, stop_reason "refusal" — reading content[0] crashes.
        Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8)
    }

    /// AC-5: HTTP 429 ⇒ `.rateLimited` (not `.apiError`).
    /// Stated sensitivity: map 429 → `.apiError` → the `.rateLimited` match fails
    /// → RED. (The scaffold maps 429→.apiError → RED now.)
    @Test
    func http429MapsToRateLimited() async {
        let scenario = StubScenario(response: .http(status: 429, headers: ["retry-after": "30"], body: Data()))
        await Self.expectThrows(Self.cleaner(for: scenario)) { error in
            guard case .rateLimited = error else { return "expected .rateLimited, got \(error)" }
            return nil
        }
    }

    /// AC-5: a transport error (no network) ⇒ `.offline`.
    @Test
    func transportErrorMapsToOffline() async {
        let scenario = StubScenario(response: .transportError(URLError(.notConnectedToInternet)))
        await Self.expectThrows(Self.cleaner(for: scenario)) { error in
            guard case .offline = error else { return "expected .offline, got \(error)" }
            return nil
        }
    }

    /// AC-5: HTTP 200 + stop_reason "refusal" ⇒ `.refused` (must not crash on
    /// the empty content array).
    @Test
    func refusal200MapsToRefused() async {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.refusalBody()))
        await Self.expectThrows(Self.cleaner(for: scenario)) { error in
            guard case .refused = error else { return "expected .refused, got \(error)" }
            return nil
        }
    }

    /// AC-5: a 2xx with a `type=="text"` block ⇒ the parsed text. The text block
    /// is NOT at content[0], so a `content[0]` reader returns the wrong value.
    /// Stated sensitivity: read `content[0]` instead of `first{type=="text"}` →
    /// returns nil/"" instead of the text → RED. (The scaffold reads content[0] → RED.)
    @Test
    func success200ReturnsParsedTextBlock() async throws {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned prose")))
        let output = try await Self.cleaner(for: scenario).clean("raw", config: Self.config, context: Self.context)
        #expect(output == "cleaned prose", "must return the type==text block's text, got \(output)")
    }

    /// AC-6: the recorded outbound request carries the §18.6 pins — header
    /// `anthropic-version: 2023-06-01`, configured model, a user message.
    /// Stated sensitivity: drift the model id or the header → the recorded-request
    /// assertion fails → RED (the "stub can't green while the real API 400s" guard).
    @Test
    func outboundRequestMatchesPinnedShape() async throws {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "ok")))
        _ = try await Self.cleaner(for: scenario).clean("the transcript", config: Self.config, context: Self.context)

        try #require(scenario.recordedRequests.count == 1, "exactly one request expected")
        let (request, body) = scenario.recordedRequests[0]
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01",
                "anthropic-version header must be 2023-06-01")

        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "claude-haiku-4-5",
                "model must be claude-haiku-4-5, got \(String(describing: json?["model"]))")
        #expect(json?["temperature"] as? Double == 0,
                "cleanup requests must use deterministic decoding")
        let messages = json?["messages"] as? [[String: Any]]
        #expect(messages?.first?["role"] as? String == "user", "messages[0].role must be user")
    }

    /// A non-default Anthropic model configured in the composition reaches the HTTP
    /// request body.
    /// Stated sensitivity: keep `PromptBuilder` hard-coded to the default model ->
    /// request model remains `claude-haiku-4-5` and this goes RED.
    @Test
    func configuredAnthropicModelReachesRequestBody() async throws {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "ok")))
        let cleaner = AnthropicCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeKeyProvider(.success("synthetic-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )

        _ = try await cleaner.clean(
            "the transcript",
            config: CleanupConfig(model: "claude-test-model", writingStyle: .formal, language: .auto),
            context: Self.context
        )

        try #require(scenario.recordedRequests.count == 1, "exactly one request expected")
        let (_, body) = scenario.recordedRequests[0]
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "claude-test-model",
                "model must be the configured Anthropic model, got \(String(describing: json?["model"]))")
    }

    /// AC-7: fail-closed — a transport error issues EXACTLY ONE outbound POST
    /// (no retry that re-sends the transcript body).
    /// Stated sensitivity: a 3× re-POST loop → recordedRequests.count == 3 → RED.
    /// (The scaffold retries 3× → count 3 → RED now.) Recovery is the
    /// FallbackCleaner→PassThrough path, never an in-cleaner re-send.
    @Test
    func failClosedSendsExactlyOneRequest() async {
        let scenario = StubScenario(response: .transportError(URLError(.timedOut)))
        _ = try? await Self.cleaner(for: scenario).clean("the transcript", config: Self.config, context: Self.context)

        #expect(scenario.recordedRequests.count == 1,
                "fail-closed: exactly one outbound POST, got \(scenario.recordedRequests.count) (re-send?)")
    }

    // MARK: - Reviewer-prescribed fixes

    /// FIX #1 (Dalek — untested arm): a key-sourcing failure ⇒ `.missingKey`
    /// (the key value never enters the error).
    /// Stated sensitivity: the `.missingKey` arm is uncovered today, so mutating
    /// production `catch { throw .missingKey }` → `throw .offline` stays GREEN
    /// without this test. With this test, that mutation goes RED. (Proven RED
    /// out-of-band via that mutation.)
    @Test
    func keySourcingFailureMapsToMissingKey() async {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "ok")))
        let cleaner = AnthropicCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeKeyProvider(.failure(.missingKey)),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )
        await Self.expectThrows(cleaner) { error in
            guard case .missingKey = error else { return "expected .missingKey, got \(error)" }
            return nil
        }
    }

    /// FIX #3 (Cyberman MAJOR + Zygon — AC-8 non-vacuity): the cleaner must
    /// ACTUALLY exercise the log sink on a normal run, so the 5-channel sentinel
    /// sweep is not green-by-construction (a cleaner that logs nothing can never
    /// leak). After a successful `clean`, the capturing sink has ≥1 coarse line.
    /// Stated sensitivity: a cleaner that emits no log lines → `captured` empty →
    /// RED now. (The implementer adds coarse, payload-free lines — status/length
    /// only — which the sentinel sweep then proves carry NO sentinel.)
    @Test
    func cleanerEmitsAtLeastOneCoarseLogLineOnSuccess() async throws {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned")))
        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "slovo", category: "cleaner-test") { captured.append($0) }
        let cleaner = AnthropicCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeKeyProvider(.success("synthetic-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3),
            log: log
        )

        _ = try await cleaner.clean("raw", config: Self.config, context: Self.context)

        #expect(!captured.isEmpty,
                "the cleaner must emit ≥1 coarse operational log line on a normal run, so the sentinel sweep is non-vacuous")
    }

    /// A process should ask Keychain for the secret at most once; every later
    /// cleanup uses the in-memory copy.
    /// Stated sensitivity: remove the provider cache -> two `clean` calls invoke
    /// the secret reader twice -> RED.
    @Test
    func keyProviderCachesSecretAcrossCleanupCalls() async throws {
        let reads = Mutex<Int>(0)
        let keyProvider = KeychainAnthropicKeyProvider(
            readKey: {
                reads.withLock { $0 += 1 }
                return "synthetic-key"
            },
            keyExists: { true },
            writeKey: { _ in }
        )
        let first = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "one")))
        let second = StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "two")))

        _ = try await AnthropicCleaner(
            session: first.makeSession(),
            keyProvider: keyProvider,
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        ).clean("raw one", config: Self.config, context: Self.context)
        _ = try await AnthropicCleaner(
            session: second.makeSession(),
            keyProvider: keyProvider,
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        ).clean("raw two", config: Self.config, context: Self.context)

        #expect(reads.withLock { $0 } == 1,
                "one process-scoped key provider must read the Keychain secret once")
    }

    /// Updating the key is rare but supported: save to durable storage and replace
    /// the in-memory key immediately.
    /// Stated sensitivity: forget to update the cache in `store` -> `apiKey()`
    /// calls the secret reader or returns the old key -> RED.
    @Test
    func storingKeyUpdatesMemoryCacheWithoutSecretRead() throws {
        let reads = Mutex<Int>(0)
        let writes = Mutex<[String]>([])
        let keyProvider = KeychainAnthropicKeyProvider(
            readKey: {
                reads.withLock { $0 += 1 }
                return "old-key"
            },
            keyExists: { true },
            writeKey: { key in writes.withLock { $0.append(key) } }
        )

        try keyProvider.store(" new-key \n")

        #expect(try keyProvider.apiKey() == "new-key",
                "the updated key must be available from memory immediately")
        #expect(reads.withLock { $0 } == 0,
                "reading after store must not re-open Keychain")
        #expect(writes.withLock { $0 } == ["new-key"],
                "durable storage receives the trimmed replacement key")
    }

    // MARK: - Helper: assert `clean` throws a CleanupError matching `check`
    // (CleanupError is not Equatable, so match via a closure returning an error
    // message or nil-on-match).
    private static func expectThrows(
        _ cleaner: AnthropicCleaner,
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
