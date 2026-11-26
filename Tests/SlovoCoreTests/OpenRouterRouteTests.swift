import Foundation
import Synchronization
import Testing

@testable import SlovoCore
import SlovoTestSupport

@Suite("Cleanup route through the OpenRouter adapter")
struct OpenRouterRouteTests {
    private static let sentinelTranscript = "S3NT1NEL-OPENROUTER-TRANSCRIPT-2d2b-DO-NOT-LOG"
    private static let sentinelCleaned = "S3NT1NEL-OPENROUTER-CLEANED-59fe-DO-NOT-LOG"
    private static let sentinelVocab = "S3NT1NEL-OPENROUTER-VOCAB-bd04-DO-NOT-LOG"
    private static let sentinelBody = "S3NT1NEL-OPENROUTER-BODY-d09b-DO-NOT-LOG"
    private static let sentinelKey = "S3NT1NEL-OPENROUTER-KEY-18e7-DO-NOT-LOG"

    private static var config: CleanupConfig {
        CleanupConfig(model: "openai/gpt-6-luna", writingStyle: .casual)
    }

    private static var context: PersonalizationContext {
        PersonalizationContext(vocabulary: [])
    }

    private static func successBody(text: String) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: ["choices": [["message": ["role": "assistant", "content": text]]]]
        )
    }

    /// The route the app builds, over the OpenRouter adapter reading `scenario`'s stubbed session.
    private static func route(
        _ scenario: StubScenario,
        keyProvider: any OpenRouterKeyProvider = FakeOpenRouterKeyProvider(.success("synthetic-openrouter-key")),
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "cleaner")
    ) -> CleanupRoute {
        CleanupRoute(
            providers: CleanupProviders(
                openRouter: OpenRouterProvider(session: scenario.makeSession(), keyProvider: keyProvider)
            ),
            promptBuilder: PromptBuilder(),
            log: log
        )
    }

    /// Stated sensitivity: using the old OpenAI Responses endpoint/body, omitting
    /// the configured routed model, sending an unauthenticated request, letting
    /// the provider's default reasoning mode stand (no `reasoning.effort: none` in
    /// the body), or sending any `max_tokens` in the body makes the recorded
    /// request-shape assertions go RED. Adding any body field (a device or user
    /// identifier, say) or any request header makes the exact key-set assertions RED.
    @Test
    func outboundRequestUsesOpenRouterChatCompletionsShapeAndConfiguredModel() async throws {
        let scenario = try StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "cleaned")))
        let cleaner = Self.route(scenario)

        _ = try await cleaner.clean("raw transcript", config: Self.config, context: Self.context)

        try #require(scenario.recordedRequests.count == 1, "exactly one request expected")
        let (request, body) = scenario.recordedRequests[0]
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer synthetic-openrouter-key")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://github.com/Akurganow/slovo")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Slovo")
        // URLSession adds Content-Length to a request with a body; the stub adds its routing header.
        let sentHeaders = Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() })
            .subtracting(["content-length", StubURLProtocol.scenarioHeader.lowercased()])
        #expect(sentHeaders == ["authorization", "content-type", "http-referer", "x-title"],
                "the request carries exactly the headers the cleaner sets, got \(sentHeaders.sorted())")

        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(json.keys) == ["model", "messages", "temperature", "reasoning"],
                "the body carries exactly these fields, got \(json.keys.sorted())")
        #expect(json["model"] as? String == "openai/gpt-6-luna")
        #expect(json["temperature"] as? Double == 0)
        #expect(json["max_tokens"] == nil,
                "no max_tokens: the response ceiling is the model's own, never a silent truncation point")
        let reasoning = try #require(
            json["reasoning"] as? [String: Any],
            "reasoning must be pinned off; provider defaults enable it on some models"
        )
        #expect(reasoning["effort"] as? String == "none")
        #expect(Set(reasoning.keys) == ["effort"])
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.allSatisfy { Set($0.keys) == ["role", "content"] })
        #expect(messages.map(\.["role"]) == ["system", "user"])
        #expect(messages.first?["content"]?.contains("Return only the cleaned transcript") == true)
        #expect(messages.last?["content"] == "<transcript>raw transcript</transcript>")
    }

    /// Stated sensitivity: pass `.shared` or any other session from the public init,
    /// drop the resource-timeout line, or build it from the default configuration -> RED.
    @Test
    func cleanupSessionEndsEveryRequestAfterTenSeconds() {
        let provider = OpenRouterProvider(keyProvider: FakeOpenRouterKeyProvider(.success("synthetic-openrouter-key")))
        #expect(provider.session.configuration.timeoutIntervalForResource == 10)
        // No disk cache: a cleanup reply holds the user's words.
        #expect((provider.session.configuration.urlCache?.diskCapacity ?? 0) == 0)
    }

    /// Stated sensitivity: parsing only OpenAI Responses API `output_text`, or
    /// reading the wrong Chat Completions field, returns no cleaned text.
    /// Trimming the returned content (`.trimmingCharacters(in: .whitespacesAndNewlines)`)
    /// turns the `"Hello\n"` and leading-space rows RED: the reply must come back as sent.
    @Test(arguments: ["cleaned prose", "Hello\n", " leading space"])
    func success200ReturnsAssistantMessageContent(reply: String) async throws {
        let scenario = try StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: reply)))
        let cleaner = Self.route(scenario)

        let output = try await cleaner.clean("raw", config: Self.config, context: Self.context)

        #expect(output == reply)
    }

    /// Stated sensitivity: reading the cost from another field (`total_tokens`, say), or decoding
    /// `usage` strictly so that a malformed one fails the reply, turns the `usage` rows RED: the
    /// cleaned text must come back whatever `usage` holds, with no cost unless it is a number.
    @Test(arguments: [
        (#","usage":{"prompt_tokens":18,"completion_tokens":3,"total_tokens":21,"cost":4.95e-06}"#, 4.95e-06 as Double?),
        ("", nil),
        (#","usage":null"#, nil),
        (#","usage":"unavailable""#, nil),
        (#","usage":{"prompt_tokens":18}"#, nil),
        (#","usage":{"cost":"free"}"#, nil),
    ])
    func reportedCostIsUsageCostAndNeverFailsTheReply(usage: String, expectedCost: Double?) async throws {
        let body = Data(#"{"choices":[{"message":{"role":"assistant","content":"cleaned"}}]\#(usage)}"#.utf8)
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: body))
        let cleaner = Self.route(scenario)

        let reply = try await cleaner.cleanReportingCost("raw", config: Self.config, context: Self.context, hints: CleanupHints())

        #expect(reply.text == "cleaned")
        #expect(reply.costUSD == expectedCost)
    }

    /// Stated sensitivity: add a retry loop on transport failure -> the transcript
    /// is sent more than once and the request count assertion fails.
    @Test
    func failClosedSendsExactlyOneRequest() async {
        let scenario = StubScenario(response: .transportError(URLError(.timedOut)))
        let cleaner = Self.route(scenario)

        _ = try? await cleaner.clean("raw transcript", config: Self.config, context: Self.context)

        #expect(scenario.recordedRequests.count == 1,
                "fail-closed: exactly one outbound POST, got \(scenario.recordedRequests.count)")
    }

    /// Stated sensitivity: mapping every code to `offline` -> the rows other than
    /// `offline` go RED, because the log loses the transport cause and the thrown
    /// case is the wrong one. The thrown case carries the token's name in every row.
    @Test(arguments: [
        (URLError.Code.timedOut, "timedOut"),
        (.notConnectedToInternet, "offline"),
        (.networkConnectionLost, "offline"),
        (.dataNotAllowed, "offline"),
        (.internationalRoamingOff, "offline"),
        (.callIsActive, "offline"),
        (.secureConnectionFailed, "tls"),
        (.serverCertificateHasBadDate, "tls"),
        (.serverCertificateUntrusted, "tls"),
        (.serverCertificateHasUnknownRoot, "tls"),
        (.serverCertificateNotYetValid, "tls"),
        (.clientCertificateRejected, "tls"),
        (.cannotFindHost, "transport"),
    ])
    func transportFailureLogsItsCauseAndThrowsTheMatchingCase(code: URLError.Code, token: String) async {
        let scenario = StubScenario(response: .transportError(URLError(code)))
        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "slovo", category: "openrouter-route-test") { captured.append($0) }
        let cleaner = Self.route(scenario, log: log)

        await Self.expectThrows(cleaner) { error in
            "\(error)" == token ? nil : "expected the case named \(token), got \(error)"
        }
        #expect(captured.contains("cleanup failed: \(token)"),
                "expected the log to name the transport cause \(token), got \(captured)")
    }

    /// Stated sensitivity: logging the non-HTTP branch under another token
    /// (`offline`, say) -> RED, because the log loses the cause. Throwing
    /// `.transport` instead of `.badResponse` -> RED.
    @Test
    func nonHTTPResponseLogsBadResponseAndThrowsBadResponse() async {
        let scenario = StubScenario(response: .nonHTTP)
        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "slovo", category: "openrouter-route-test") { captured.append($0) }
        let cleaner = Self.route(scenario, log: log)

        await Self.expectThrows(cleaner) { error in
            guard case .badResponse = error else { return "expected .badResponse, got \(error)" }
            return nil
        }
        #expect(captured.contains("cleanup failed: badResponse"),
                "expected the log to name badResponse, got \(captured)")
    }

    /// Stated sensitivity: mapping 429 to a generic failure makes the fallback
    /// lose throttling information.
    @Test
    func http429MapsToRateLimited() async {
        let scenario = StubScenario(response: .http(status: 429, headers: ["retry-after": "5"], body: Data()))
        let cleaner = Self.route(scenario)

        await Self.expectThrows(cleaner) { error in
            guard case .rateLimited(let retryAfter) = error else { return "expected .rateLimited, got \(error)" }
            guard retryAfter == 5 else { return "expected retry-after 5, got \(String(describing: retryAfter))" }
            return nil
        }
    }

    /// Stated sensitivity: letting a raw DecodingError escape on malformed 2xx
    /// bypasses `FallbackCleaner`'s CleanupError degradation path. Bypassing the
    /// visible-character predicate in `firstText` (back to `!content.isEmpty`)
    /// leaves this test GREEN, because the route's own guard still throws; the
    /// route's guard is pinned by `aReplyWithNoVisibleTextThrowsNoText`, and
    /// `firstText` itself by `firstTextTakesTheFirstChoiceWithVisibleText`.
    @Test(arguments: [
        #"{}"#,
        #"{"choices":[{"message":{"role":"assistant","content":" \n\t"}}]}"#,
    ])
    func malformed200MapsToCleanupError(body: String) async {
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Data(body.utf8)))
        let cleaner = Self.route(scenario)

        await Self.expectThrows(cleaner) { error in
            guard case .noText = error else { return "expected .noText, got \(error)" }
            return nil
        }
    }

    /// Stated sensitivity: a key-sourcing error must not become another case.
    @Test
    func keySourcingFailureMapsToMissingKey() async throws {
        let scenario = try StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "ok")))
        let cleaner = Self.route(scenario, keyProvider: FakeOpenRouterKeyProvider(.failure(.missingKey)))

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
            writeKey: { _ in },
            deleteKey: { }
        )
        let first = try StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "one")))
        let second = try StubScenario(response: .http(status: 200, headers: [:], body: Self.successBody(text: "two")))

        _ = try await Self.route(first, keyProvider: keyProvider)
            .clean("raw one", config: Self.config, context: Self.context)
        _ = try await Self.route(second, keyProvider: keyProvider)
            .clean("raw two", config: Self.config, context: Self.context)

        #expect(reads.withLock { $0 } == 1,
                "one process-scoped OpenRouter key provider must read the Keychain secret once")
    }

    /// Stated sensitivity: logging the request body, response body, output, or
    /// bearer key makes the matching synthetic sentinel reach the capturing sink.
    @Test
    func openRouterPayloadChannelsNeverReachLog() async throws {
        let body = Data(#"{"error":{"message":"\#(Self.sentinelBody)"}}"#.utf8)
        let cases: [(String, FakeOpenRouterKeyProvider.Outcome, StubResponse, String, [Term])] = try [
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

    /// What the adapter alone says about an HTTP status. The route re-fetches the key's
    /// model scope after `.modelUnavailable`, so the 404 row is the one that matters.
    /// Stated sensitivity: map 404 to `.refused` -> the 404 row goes RED (the scope
    /// re-fetch would stop with every other test green); map 401 or 500 to
    /// `.modelUnavailable` -> those rows go RED.
    @Test(arguments: [(404, "modelUnavailable"), (401, "refused"), (500, "refused")])
    func httpErrorStatusMapsToModelUnavailableOrRefused(status: Int, expected: String) async {
        let scenario = StubScenario(response: .http(status: status, headers: [:], body: Data()))
        let provider = OpenRouterProvider(
            session: scenario.makeSession(),
            keyProvider: FakeOpenRouterKeyProvider(.success("synthetic-openrouter-key"))
        )
        let prompt = CleanupPrompt(model: "m", prefixBlocks: ["system"], advisory: nil, input: "<transcript>raw</transcript>")

        do {
            _ = try await provider.reply(to: prompt)
            #expect(Bool(false), "expected status \(status) to throw")
        } catch {
            #expect("\(error)" == expected, "status \(status) must map to \(expected), got \(error)")
        }
    }

    /// Stated sensitivity: delete the route's visible-text guard -> the whitespace rows
    /// return instead of throwing -> RED.
    @Test(arguments: ["", " \n\t"])
    func aReplyWithNoVisibleTextThrowsNoText(text: String) async {
        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "slovo", category: "openrouter-route-test") { captured.append($0) }
        let route = Self.route(replying: text, log: log)

        await Self.expectThrows(route) { error in
            guard case .noText = error else { return "expected .noText, got \(error)" }
            return nil
        }
        #expect(captured == ["cleanup failed: apiError"], "got \(captured)")
    }

    /// The outcome line for the failures no other test pins: the transport and
    /// non-HTTP rows are `transportFailureLogsItsCauseAndThrowsTheMatchingCase` and
    /// `nonHTTPResponseLogsBadResponseAndThrowsBadResponse`. A missing key writes
    /// no line; every other failure writes its one fixed token. The error is
    /// rethrown as it came.
    /// Stated sensitivity: give `.missingKey` an outcome line -> RED; map `.noText`,
    /// `.refused` or `.modelUnavailable` to another token -> RED; map `.rateLimited`
    /// to `apiError` -> RED; swallow or replace the error -> RED.
    @Test(arguments: [
        (CleanupError.missingKey, String?.none),
        (.rateLimited(retryAfter: nil), "cleanup failed: rateLimited"),
        (.modelUnavailable, "cleanup failed: apiError"),
        (.refused, "cleanup failed: apiError"),
        (.noText, "cleanup failed: apiError"),
    ])
    func routeLogsTheFixedTokenOfEachFailure(error: CleanupError, line: String?) async {
        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "slovo", category: "openrouter-route-test") { captured.append($0) }
        let route = CleanupRoute(
            providers: CleanupProviders(openRouter: ThrowingProvider(error: error)),
            promptBuilder: PromptBuilder(),
            log: log
        )

        await Self.expectThrows(route) { thrown in
            "\(thrown)" == "\(error)" ? nil : "expected \(error) rethrown, got \(thrown)"
        }
        #expect(captured == (line.map { [$0] } ?? []), "got \(captured)")
    }

    /// The reply's first choice with a visible character wins; a choice without
    /// one is skipped, and none at all is no text.
    /// Stated sensitivity: return the first non-nil content (drop the visible-character
    /// check) -> the first row returns " \n" -> RED; return only the first choice's
    /// content -> RED.
    @Test(arguments: [
        (#"{"choices":[{"message":{"content":" \n"}},{"message":{"content":"real"}}]}"#, String?.some("real")),
        (#"{"choices":[{"message":{"content":" \n"}}]}"#, nil),
    ])
    func firstTextTakesTheFirstChoiceWithVisibleText(body: String, expected: String?) throws {
        let response = try JSONDecoder().decode(OpenRouterResponse.self, from: Data(body.utf8))

        #expect(response.firstText == expected)
    }

    private static func route(replying text: String, log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "cleaner")) -> CleanupRoute {
        CleanupRoute(
            providers: CleanupProviders(openRouter: FixedProvider(text: text)),
            promptBuilder: PromptBuilder(),
            log: log
        )
    }

    private struct ThrowingProvider: CleanupProvider {
        let error: CleanupError

        func reply(to prompt: CleanupPrompt) async throws -> CleanupReply {
            throw error
        }
    }

    private struct FixedProvider: CleanupProvider {
        let text: String

        func reply(to prompt: CleanupPrompt) async throws -> CleanupReply {
            CleanupReply(text: text)
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
        let log = RedactionSafeLog(subsystem: "slovo", category: "openrouter-route-test") { captured.append($0) }
        let cleaner = Self.route(scenario, keyProvider: FakeOpenRouterKeyProvider(keyOutcome), log: log)
        _ = try? await cleaner.clean(
            raw,
            config: Self.config,
            context: PersonalizationContext(vocabulary: vocabulary)
        )
        return captured
    }

    private static func expectThrows(
        _ cleaner: CleanupRoute,
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
