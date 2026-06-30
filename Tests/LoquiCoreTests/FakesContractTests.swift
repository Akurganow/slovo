import Foundation
import Testing

import LoquiCore
import LoquiTestSupport

// Epic 02 — AC-4 (a fake honors the seam contract) and AC-6 (the port returns
// terms unchanged; consumer stays GRDB-free).
//
// Contract under test (implementer builds the REAL fakes in a new
// `Sources/LoquiTestSupport/` target per plan §3/§6; the symbols are CURRENTLY
// supplied by the WRONG-ON-PURPOSE `_RedScaffold_Fakes.swift` stub —
// `FakeCleaner` swallows the programmed failure and records nothing,
// `FakePersonalizationSource` drops its terms — so these tests go RED).
//
//     final class FakeCleaner: Cleaner {
//         enum Outcome { case success(String); case failure(CleanupError) }
//         private(set) var calls: [(raw:…, config:…, context:…)]
//         init(outcome: Outcome)
//     }
//     final class FakePersonalizationSource: PersonalizationSource {
//         init(terms: [Term]) ; func vocabulary(limit: Int) -> [Term]
//     }
@Suite("Epic 02 AC-4/AC-6 fakes")
struct FakesContractTests {

    // MARK: - AC-4: fake throws the EXACT programmed case and records the call

    /// Stated sensitivity: the fake SWALLOWS the error (returns a string) → the
    /// "did not throw" branch records an issue → RED. The fake throws a DIFFERENT
    /// case (`.missingKey`) → the `switch` "wrong case" branch records → RED. So
    /// the test pins the EXACT programmed case, not merely "some error". (The
    /// scaffold swallows, so it REDs the first branch now.)
    @Test
    func fakeCleanerThrowsExactProgrammedCase() async {
        let fake = FakeCleaner(outcome: .failure(.offline))
        let config = CleanupConfig(writingStyle: .formal, language: .en)
        let context = PersonalizationContext(vocabulary: [])

        do {
            _ = try await fake.clean("hello", config: config, context: context)
            Issue.record("FakeCleaner(.failure(.offline)) did not throw — error swallowed")
        } catch let error as CleanupError {
            switch error {
            case .offline:
                break  // correct — exactly the programmed case
            case .missingKey, .rateLimited, .apiError, .refused:
                Issue.record("FakeCleaner threw the wrong CleanupError case: \(error)")
            }
        } catch {
            Issue.record("FakeCleaner threw a non-CleanupError: \(error)")
        }
    }

    /// AC-4: the fake records the call it received (args captured), so tests can
    /// assert the seam was driven with the expected inputs.
    /// Stated sensitivity: the fake does not record → `calls` is empty → RED.
    @Test
    func fakeCleanerRecordsTheCall() async {
        let fake = FakeCleaner(outcome: .failure(.offline))
        let config = CleanupConfig(writingStyle: .casual, language: .ru)
        let context = PersonalizationContext(vocabulary: [])

        _ = try? await fake.clean("raw transcript", config: config, context: context)

        #expect(fake.calls.count == 1, "the fake must record exactly one call, got \(fake.calls.count)")
        #expect(fake.calls.first?.raw == "raw transcript",
                "the fake must capture the raw argument it was called with")
    }

    // MARK: - AC-6: port returns the terms unchanged (order + values)

    /// Stated sensitivity: the fake drops / reorders / mutates the terms (the
    /// scaffold returns []) → the order-and-values comparison fails → RED. The
    /// consumer holds only the protocol type, so it needs no GRDB import (the
    /// Epic-01 dependency-direction gate stays green; no new `import GRDB`).
    @Test
    func portReturnsTermsUnchanged() {
        let t1 = Term(term: "alpha", expansion: nil, lang: .en, weight: 1)
        let t2 = Term(term: "beta", expansion: "b", lang: .ru, weight: 2)
        let t3 = Term(term: "gamma", expansion: nil, lang: .auto, weight: 3)

        // The consumer sees only the protocol — it never touches persistence.
        let source: PersonalizationSource = FakePersonalizationSource(terms: [t1, t2, t3])
        let received = source.vocabulary(limit: 3)

        #expect(received.count == 3, "expected 3 terms, got \(received.count)")
        // Compare by identifying fields (Term is not Equatable per §18.3) to prove
        // order AND values are preserved exactly.
        let projection = received.map { "\($0.term)|\($0.expansion ?? "∅")|\($0.lang)|\($0.weight)" }
        #expect(projection == ["alpha|∅|en|1", "beta|b|ru|2", "gamma|∅|auto|3"],
                "terms must come back unchanged in order; got \(projection)")
    }
}
