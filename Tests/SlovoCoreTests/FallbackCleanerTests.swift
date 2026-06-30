import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Epic 06 — AC-1 (every CleanupError ⇒ advance to PassThrough, raw inserted),
// AC-2 (a NON-CleanupError PROPAGATES, no silent degrade), AC-9 (`.refused`
// advances WITH a user-visible status).
//
// Contract under test (implementer builds `Sources/SlovoCore/Cleaner/FallbackCleaner.swift`
// per plan §4; CURRENTLY the WRONG-ON-PURPOSE `_RedScaffold_Cleaner.swift` stub
// uses a BARE catch that advances everything silently — so AC-2 + AC-9 RED. AC-1
// is GREEN on this scaffold; its RED (a terminal, non-advancing case) is proven
// out-of-band).
//
// `CleanupError` is NOT Equatable: AC-1 asserts via the returned raw; AC-2 via a
// `#expect(throws:)` + `switch`; AC-9 via the Equatable StatusMessage callback.
@Suite("Epic 06 AC-1/AC-2/AC-9 FallbackCleaner")
struct FallbackCleanerTests {
    private static let raw = "Um, so like, запушь the PR"
    private static var config: CleanupConfig { CleanupConfig(writingStyle: .formal, language: .auto) }
    private static var context: PersonalizationContext { PersonalizationContext(vocabulary: []) }

    private static func fallback(
        _ chain: [Cleaner], report: @escaping (StatusMessage) -> Void = { _ in }
    ) -> FallbackCleaner {
        FallbackCleaner(chain: chain, statusReporter: report)
    }

    /// AC-1: every `CleanupError` case ⇒ the chain advances to `PassThrough`,
    /// returning the raw input unchanged.
    /// Stated sensitivity: make a case "terminal" (re-throw instead of advancing)
    /// → that case throws instead of returning raw → RED. (Proven out-of-band:
    /// the scaffold's bare-catch advances all cases, so this is GREEN here; a
    /// non-advancing mutation REDs it.)
    @Test
    func everyCleanupErrorAdvancesToPassThrough() async throws {
        let cases: [CleanupError] = [
            .offline, .missingKey, .rateLimited(retryAfter: 1.0), .apiError(status: 500), .refused,
        ]
        for failure in cases {
            let chain: [Cleaner] = [FakeCleaner(outcome: .failure(failure)), PassThrough()]
            let output = try await Self.fallback(chain).clean(Self.raw, config: Self.config, context: Self.context)
            #expect(output == Self.raw, "a \(failure) failure must degrade to PassThrough (raw inserted), got \(output)")
        }
    }

    /// AC-2: a NON-`CleanupError` (here `CancellationError`) must PROPAGATE —
    /// not be swallowed and degraded.
    /// Stated sensitivity: `catch let e as CleanupError` → bare `catch` → the
    /// CancellationError is swallowed + degraded → does NOT throw → RED. (The
    /// scaffold uses a bare catch → swallows → RED now.)
    @Test
    func nonCleanupErrorPropagates() async {
        let chain: [Cleaner] = [ThrowingCleaner(CancellationError()), PassThrough()]
        var threw = false
        do {
            _ = try await Self.fallback(chain).clean(Self.raw, config: Self.config, context: Self.context)
        } catch is CancellationError {
            threw = true
        } catch {
            #expect(Bool(false), "expected CancellationError to propagate, got \(error)")
        }
        #expect(threw, "a non-CleanupError must propagate, not be swallowed and degraded to PassThrough")
    }

    /// AC-9: `.refused` advances to `PassThrough` WITH the user-visible
    /// `.cleanupDeclinedInsertedAsSpoken` status (not silent).
    /// Stated sensitivity: advance on `.refused` silently (don't call
    /// statusReporter) → recorded statuses empty → RED. (The scaffold advances
    /// silently → RED now.)
    @Test
    func refusedAdvancesWithVisibleStatus() async throws {
        var reported: [StatusMessage] = []
        let chain: [Cleaner] = [FakeCleaner(outcome: .failure(.refused)), PassThrough()]
        let output = try await Self.fallback(chain, report: { reported.append($0) })
            .clean(Self.raw, config: Self.config, context: Self.context)

        #expect(output == Self.raw, "`.refused` must still degrade to PassThrough (raw inserted)")
        #expect(reported == [.cleanupDeclinedInsertedAsSpoken],
                "`.refused` must report .cleanupDeclinedInsertedAsSpoken (visible, not silent), got \(reported)")
    }

    /// AC-9 distinguisher: a SILENT case (`.offline`) must NOT call the reporter
    /// (guards against an over-eager reporter that fires on every case).
    @Test
    func silentCaseDoesNotReport() async throws {
        var reported: [StatusMessage] = []
        let chain: [Cleaner] = [FakeCleaner(outcome: .failure(.offline)), PassThrough()]
        _ = try await Self.fallback(chain, report: { reported.append($0) })
            .clean(Self.raw, config: Self.config, context: Self.context)

        #expect(reported.isEmpty, "a silent CleanupError case must NOT call the statusReporter, got \(reported)")
    }

    /// FIX #2 (Racnoss — "never lose the words"): a malformed 2xx body (valid
    /// HTTP 200 but NOT a decodable AnthropicResponse) must DEGRADE through the
    /// chain to `PassThrough` (raw transcript inserted) — it must NOT throw a
    /// non-CleanupError that escapes the chain and strands the dictation.
    ///
    /// Stated sensitivity: RED now — the real `AnthropicCleaner` does
    /// `try JSONDecoder().decode(...)`, so a malformed 2xx throws a raw
    /// `DecodingError`. That is NOT a `CleanupError`, so the typed
    /// `catch let error as CleanupError` in `FallbackCleaner` does NOT catch it →
    /// it escapes the chain (PassThrough never runs) → the "returns raw" assertion
    /// fails / an unexpected error throws → RED. The fix: a malformed 2xx maps to
    /// a `CleanupError` so the chain degrades.
    @Test
    func malformed200DegradesToPassThrough() async throws {
        // Valid HTTP 200, but the body is not a decodable AnthropicResponse.
        let scenario = StubScenario(response: .http(status: 200, headers: [:], body: Data("{}".utf8)))
        let cleaner = AnthropicCleaner(
            session: scenario.makeSession(),
            keyProvider: FakeKeyProvider(.success("synthetic-key")),
            promptBuilder: PromptBuilder(maxVocabularyTerms: 3)
        )
        let chain: [Cleaner] = [cleaner, PassThrough()]

        var output: String?
        do {
            output = try await Self.fallback(chain).clean(Self.raw, config: Self.config, context: Self.context)
        } catch {
            #expect(Bool(false), "a malformed 2xx must degrade (not throw a non-CleanupError that escapes the chain), got \(error)")
        }
        #expect(output == Self.raw,
                "a malformed 2xx must degrade to PassThrough (raw inserted), got \(String(describing: output))")
    }
}
