import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Fallback cleanup must preserve insertion when upstream cleanup fails
// while still propagating non-cleanup failures.
@Suite("FallbackCleaner")
struct FallbackCleanerTests {
    private static let raw = "Um, so like, запушь the PR"
    private static var config: CleanupConfig { CleanupConfig(writingStyle: .formal) }
    private static var context: PersonalizationContext { PersonalizationContext(vocabulary: []) }

    private static func fallback(
        _ cleaner: Cleaner, report: @escaping (StatusMessage) -> Void = { _ in }
    ) -> FallbackCleaner {
        FallbackCleaner(cleaner: cleaner, statusReporter: report)
    }

    /// A NON-`CleanupError` (here `CancellationError`) must PROPAGATE —
    /// not be swallowed and degraded.
    /// Stated sensitivity: `catch let e as CleanupError` → bare `catch` → the
    /// CancellationError is swallowed + degraded → does NOT throw → RED.
    @Test
    func nonCleanupErrorPropagates() async {
        var threw = false
        do {
            _ = try await Self.fallback(ThrowingCleaner(CancellationError())).clean(Self.raw, config: Self.config, context: Self.context)
        } catch is CancellationError {
            threw = true
        } catch {
            #expect(Bool(false), "expected CancellationError to propagate, got \(error)")
        }
        #expect(threw, "a non-CleanupError must propagate, not be swallowed and degraded to the spoken text")
    }

    /// Every expected cleanup failure falls back to the spoken text WITH the
    /// user-visible sad-to-fail status. Cleanup is always attempted upstream;
    /// insertion falls back to the direct transcript only when cleanup fails with
    /// `CleanupError` because the provider is unavailable, refused, or misconfigured.
    /// Stated sensitivity: keep any of the ten cases silent, or skip `statusReporter`
    /// altogether -> RED.
    @Test
    func expectedCleanupErrorsFallBackWithSadToFailStatus() async throws {
        let cases: [CleanupError] = [
            .missingKey, .timedOut, .offline, .tls, .transport, .badResponse,
            .rateLimited(retryAfter: 1.0), .modelUnavailable, .refused, .noText,
        ]
        for failure in cases {
            var reported: [StatusMessage] = []
            let output = try await Self.fallback(FakeCleaner(outcome: .failure(failure)), report: { reported.append($0) })
                .clean(Self.raw, config: Self.config, context: Self.context)

            #expect(output == Self.raw, "\(failure) must still fall back to the spoken text")
            #expect(reported == [.cleanupUnavailableInsertedAsSpoken],
                    "\(failure) must report sad-to-fail status, got \(reported)")
        }
    }
}
