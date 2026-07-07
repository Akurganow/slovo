import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Fallback cleanup must preserve insertion when upstream cleanup fails
// while still propagating non-cleanup failures.
@Suite("FallbackCleaner")
struct FallbackCleanerTests {
    private static let raw = "Um, so like, запушь the PR"
    private static var config: CleanupConfig { CleanupConfig(writingStyle: .formal, language: .auto) }
    private static var context: PersonalizationContext { PersonalizationContext(vocabulary: []) }

    private static func fallback(
        _ chain: [Cleaner], report: @escaping (StatusMessage) -> Void = { _ in }
    ) -> FallbackCleaner {
        FallbackCleaner(chain: chain, statusReporter: report)
    }

    /// Every `CleanupError` case ⇒ the chain advances to `PassThrough`,
    /// returning the raw input unchanged.
    /// Stated sensitivity: make a case "terminal" (re-throw instead of advancing)
    /// → that case throws instead of returning raw → RED.
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

    /// A NON-`CleanupError` (here `CancellationError`) must PROPAGATE —
    /// not be swallowed and degraded.
    /// Stated sensitivity: `catch let e as CleanupError` → bare `catch` → the
    /// CancellationError is swallowed + degraded → does NOT throw → RED.
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

    /// Every expected cleanup failure advances to `PassThrough` WITH the
    /// user-visible sad-to-fail status. Cleanup is always attempted upstream;
    /// insertion falls back to the direct transcript only when cleanup fails with
    /// `CleanupError` because the provider is unavailable, refused, or misconfigured.
    /// Stated sensitivity: keep `.offline`, `.missingKey`, `.rateLimited`, and
    /// `.apiError` silent, or keep reporting the old refused-only status -> RED.
    @Test
    func expectedCleanupErrorsAdvanceWithSadToFailStatus() async throws {
        let cases: [CleanupError] = [
            .offline, .missingKey, .rateLimited(retryAfter: 1.0), .apiError(status: 500), .refused,
        ]
        for failure in cases {
            var reported: [StatusMessage] = []
            let chain: [Cleaner] = [FakeCleaner(outcome: .failure(failure)), PassThrough()]
            let output = try await Self.fallback(chain, report: { reported.append($0) })
                .clean(Self.raw, config: Self.config, context: Self.context)

            #expect(output == Self.raw, "\(failure) must still degrade to PassThrough")
            #expect(reported == [.cleanupUnavailableInsertedAsSpoken],
                    "\(failure) must report sad-to-fail status, got \(reported)")
        }
    }
}
