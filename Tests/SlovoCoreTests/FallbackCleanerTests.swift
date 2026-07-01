import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Epic 06 — AC-1 (every CleanupError ⇒ advance to PassThrough, raw inserted),
// AC-2 (a NON-CleanupError PROPAGATES, no silent degrade), AC-9 (every expected
// cleanup provider failure surfaces the same sad-to-fail status).
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

    /// AC-9: every expected cleanup failure advances to `PassThrough` WITH the
    /// user-visible sad-to-fail status. Cleanup is optional; insertion is not.
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
